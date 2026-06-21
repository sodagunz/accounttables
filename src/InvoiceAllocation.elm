module InvoiceAllocation exposing
    ( Allocation
    , AllocationKind(..)
    , DocumentSettlement
    , DocumentStatus(..)
    , allocate
    , creditNoteSettlementFor
    , invoiceSettlementFor
    )

import Accounting exposing (Currency(..), Movement, MovementType(..))
import Allocation exposing (AllocationIntent, AllocationStrategy, TargetSelectionSource)


type AllocationKind
    = ExpenseToInvoice
    | IncomeToCreditNote
    | CreditNoteToInvoice


type DocumentStatus
    = Pending
    | PartiallySettled
    | FullySettled
    | OverSettled


type alias Allocation =
    { kind : AllocationKind
    , sourceMovementId : String
    , targetMovementId : String
    , amountInSourceCurrency : Float
    , sourceCurrency : Currency
    , amountInTargetCurrency : Float
    , targetCurrency : Currency
    , targetSelectionSource : TargetSelectionSource
    , strategy : AllocationStrategy
    }


type alias DocumentSettlement =
    { movementId : String
    , currency : Currency
    , nominalAmount : Float
    , allocatedAmount : Float
    , remainingDue : Float
    , status : DocumentStatus
    }


allocate : List Movement -> List Allocation
allocate movements =
    let
        activeMovements : List Movement
        activeMovements =
            List.filter (\movement -> movement.deletedAt == Nothing) movements

        incomeRefundAllocations : List Allocation
        incomeRefundAllocations =
            activeMovements
                |> List.filter (\movement -> movement.movementType == IncomeMovement)
                |> sortSources
                |> List.foldl
                    (\source allocations ->
                        allocations ++ allocateCashflowSource activeMovements allocations IncomeToCreditNote SupplierCreditNoteMovement source
                    )
                    []

        creditNoteOffsetAllocations : List Allocation
        creditNoteOffsetAllocations =
            activeMovements
                |> List.filter (\movement -> movement.movementType == SupplierCreditNoteMovement)
                |> sortSources
                |> List.foldl
                    (\source allocations ->
                        allocations ++ allocateCreditNoteSource activeMovements allocations source
                    )
                    incomeRefundAllocations
                |> List.drop (List.length incomeRefundAllocations)

        allocationsBeforeExpenses : List Allocation
        allocationsBeforeExpenses =
            incomeRefundAllocations ++ creditNoteOffsetAllocations

        expensePaymentAllocations : List Allocation
        expensePaymentAllocations =
            activeMovements
                |> List.filter (\movement -> movement.movementType == ExpenseMovement)
                |> sortSources
                |> List.foldl
                    (\source allocations ->
                        allocations ++ allocateCashflowSource activeMovements allocations ExpenseToInvoice SupplierInvoiceMovement source
                    )
                    allocationsBeforeExpenses
                |> List.drop (List.length allocationsBeforeExpenses)
    in
    allocationsBeforeExpenses ++ expensePaymentAllocations


allocateCashflowSource : List Movement -> List Allocation -> AllocationKind -> MovementType -> Movement -> List Allocation
allocateCashflowSource activeMovements existingAllocations kind targetType source =
    allocateSource activeMovements existingAllocations kind targetType (abs source.inputAmount) source


allocateCreditNoteSource : List Movement -> List Allocation -> Movement -> List Allocation
allocateCreditNoteSource activeMovements existingAllocations source =
    let
        nominalCredit : Float
        nominalCredit =
            abs source.inputAmount

        refundedCredit : Float
        refundedCredit =
            existingAllocations
                |> List.filter (\allocation -> allocation.kind == IncomeToCreditNote && allocation.targetMovementId == source.id)
                |> List.foldl (\allocation total -> total + allocation.amountInTargetCurrency) 0

        availableCredit : Float
        availableCredit =
            max 0 (nominalCredit - refundedCredit)
    in
    allocateSource activeMovements existingAllocations CreditNoteToInvoice SupplierInvoiceMovement availableCredit source


allocateSource : List Movement -> List Allocation -> AllocationKind -> MovementType -> Float -> Movement -> List Allocation
allocateSource activeMovements existingAllocations kind targetType sourceAmount source =
    case source.allocationIntent of
        Nothing ->
            []

        Just intent ->
            let
                selectedTargets : List Movement
                selectedTargets =
                    selectedTargetMovements activeMovements kind targetType source intent
            in
            allocateOldestDueFirst existingAllocations kind source intent sourceAmount selectedTargets


selectedTargetMovements : List Movement -> AllocationKind -> MovementType -> Movement -> AllocationIntent -> List Movement
selectedTargetMovements activeMovements kind targetType source intent =
    intent.targetIds
        |> uniqueStrings
        |> List.filterMap (findMovementById activeMovements)
        |> List.filter (eligibleTarget kind targetType source)
        |> sortTargets


eligibleTarget : AllocationKind -> MovementType -> Movement -> Movement -> Bool
eligibleTarget kind targetType source target =
    target.deletedAt
        == Nothing
        && target.accountId
        == source.accountId
        && target.movementType
        == targetType
        && (case kind of
                CreditNoteToInvoice ->
                    target.inputCurrency == source.inputCurrency

                _ ->
                    True
           )


allocateOldestDueFirst : List Allocation -> AllocationKind -> Movement -> AllocationIntent -> Float -> List Movement -> List Allocation
allocateOldestDueFirst existingAllocations kind source intent sourceAmount selectedTargets =
    case selectedTargets of
        [] ->
            []

        oldestTarget :: _ ->
            let
                initialState : AllocationState
                initialState =
                    { allocations = existingAllocations
                    , sourceAllocations = []
                    , remainingSourceAmount = sourceAmount
                    }

                allocatedState : AllocationState
                allocatedState =
                    List.foldl (allocateTarget kind source intent) initialState selectedTargets
            in
            if allocatedState.remainingSourceAmount > toleranceFor source.inputCurrency source.exchangeRate then
                let
                    overpayAllocation : Allocation
                    overpayAllocation =
                        allocationRecord kind source intent oldestTarget allocatedState.remainingSourceAmount
                in
                allocatedState.sourceAllocations ++ [ overpayAllocation ]

            else
                allocatedState.sourceAllocations


type alias AllocationState =
    { allocations : List Allocation
    , sourceAllocations : List Allocation
    , remainingSourceAmount : Float
    }


allocateTarget : AllocationKind -> Movement -> AllocationIntent -> Movement -> AllocationState -> AllocationState
allocateTarget kind source intent target state =
    let
        sourceTolerance : Float
        sourceTolerance =
            toleranceFor source.inputCurrency source.exchangeRate

        targetTolerance : Float
        targetTolerance =
            toleranceFor target.inputCurrency source.exchangeRate

        remainingDue : Float
        remainingDue =
            remainingDueFor state.allocations target

        sourceAvailableInTargetCurrency : Float
        sourceAvailableInTargetCurrency =
            convertAmount source.exchangeRate source.inputCurrency target.inputCurrency state.remainingSourceAmount

        amountInTargetCurrency : Float
        amountInTargetCurrency =
            min remainingDue sourceAvailableInTargetCurrency
    in
    if state.remainingSourceAmount <= sourceTolerance || remainingDue <= targetTolerance || amountInTargetCurrency <= targetTolerance then
        state

    else
        let
            amountInSourceCurrency : Float
            amountInSourceCurrency =
                convertAmount source.exchangeRate target.inputCurrency source.inputCurrency amountInTargetCurrency

            allocation : Allocation
            allocation =
                allocationRecord kind source intent target amountInSourceCurrency
        in
        { allocations = state.allocations ++ [ allocation ]
        , sourceAllocations = state.sourceAllocations ++ [ allocation ]
        , remainingSourceAmount = max 0 (state.remainingSourceAmount - amountInSourceCurrency)
        }


allocationRecord : AllocationKind -> Movement -> AllocationIntent -> Movement -> Float -> Allocation
allocationRecord kind source intent target amountInSourceCurrency =
    { kind = kind
    , sourceMovementId = source.id
    , targetMovementId = target.id
    , amountInSourceCurrency = amountInSourceCurrency
    , sourceCurrency = source.inputCurrency
    , amountInTargetCurrency = convertAmount source.exchangeRate source.inputCurrency target.inputCurrency amountInSourceCurrency
    , targetCurrency = target.inputCurrency
    , targetSelectionSource = intent.targetSelectionSource
    , strategy = intent.strategy
    }


invoiceSettlementFor : List Allocation -> Movement -> DocumentSettlement
invoiceSettlementFor allocations invoice =
    settlementFor invoice
        (allocations
            |> List.filter (\allocation -> allocation.targetMovementId == invoice.id)
            |> List.foldl (\allocation total -> total + allocation.amountInTargetCurrency) 0
        )


creditNoteSettlementFor : List Allocation -> Movement -> DocumentSettlement
creditNoteSettlementFor allocations creditNote =
    let
        refunded : Float
        refunded =
            allocations
                |> List.filter (\allocation -> allocation.kind == IncomeToCreditNote && allocation.targetMovementId == creditNote.id)
                |> List.foldl (\allocation total -> total + allocation.amountInTargetCurrency) 0

        applied : Float
        applied =
            allocations
                |> List.filter (\allocation -> allocation.kind == CreditNoteToInvoice && allocation.sourceMovementId == creditNote.id)
                |> List.foldl (\allocation total -> total + allocation.amountInSourceCurrency) 0
    in
    settlementFor creditNote (refunded + applied)


settlementFor : Movement -> Float -> DocumentSettlement
settlementFor document allocatedAmount =
    let
        nominalAmount : Float
        nominalAmount =
            abs document.inputAmount

        remainingDue : Float
        remainingDue =
            nominalAmount - allocatedAmount
    in
    { movementId = document.id
    , currency = document.inputCurrency
    , nominalAmount = nominalAmount
    , allocatedAmount = allocatedAmount
    , remainingDue = remainingDue
    , status = statusFor document.inputCurrency document.exchangeRate allocatedAmount remainingDue
    }


statusFor : Currency -> Float -> Float -> Float -> DocumentStatus
statusFor currency exchangeRate allocatedAmount remainingDue =
    let
        tolerance : Float
        tolerance =
            toleranceFor currency exchangeRate
    in
    if allocatedAmount <= tolerance then
        Pending

    else if remainingDue < -tolerance then
        OverSettled

    else if abs remainingDue <= tolerance then
        FullySettled

    else
        PartiallySettled


remainingDueFor : List Allocation -> Movement -> Float
remainingDueFor allocations target =
    abs target.inputAmount - allocatedAmountForTarget allocations target.id


allocatedAmountForTarget : List Allocation -> String -> Float
allocatedAmountForTarget allocations targetMovementId =
    allocations
        |> List.filter (\allocation -> allocation.targetMovementId == targetMovementId)
        |> List.foldl (\allocation total -> total + allocation.amountInTargetCurrency) 0


convertAmount : Float -> Currency -> Currency -> Float -> Float
convertAmount exchangeRate fromCurrency toCurrency amount =
    case ( fromCurrency, toCurrency ) of
        ( ARS, ARS ) ->
            amount

        ( USD, USD ) ->
            amount

        ( ARS, USD ) ->
            amount / exchangeRate

        ( USD, ARS ) ->
            amount * exchangeRate


toleranceFor : Currency -> Float -> Float
toleranceFor currency exchangeRate =
    case currency of
        USD ->
            1

        ARS ->
            exchangeRate


sortSources : List Movement -> List Movement
sortSources movements =
    List.sortWith compareByDateThenId movements


sortTargets : List Movement -> List Movement
sortTargets movements =
    List.sortWith compareByDateThenId movements


compareByDateThenId : Movement -> Movement -> Order
compareByDateThenId left right =
    case compare left.date right.date of
        EQ ->
            compare left.id right.id

        order ->
            order


findMovementById : List Movement -> String -> Maybe Movement
findMovementById movements movementId =
    movements
        |> List.filter (\movement -> movement.id == movementId)
        |> List.head


uniqueStrings : List String -> List String
uniqueStrings values =
    List.foldl
        (\value seen ->
            if List.member value seen then
                seen

            else
                seen ++ [ value ]
        )
        []
        values
