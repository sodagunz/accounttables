module InvoiceAllocationTest exposing (suite)

import Accounting exposing (Currency(..), Movement, MovementType(..))
import Allocation exposing (AllocationIntent, AllocationStrategy(..), TargetSelectionSource(..))
import Expect
import InvoiceAllocation exposing (AllocationKind(..), DocumentStatus(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "InvoiceAllocation"
        [ test "allocates expense payments oldest due first and overpays oldest selected invoice" <|
            \_ ->
                let
                    inv1 : Movement
                    inv1 =
                        movement "inv-1" SupplierInvoiceMovement "supplier" USD 100 1000 "2026-01-01" Nothing

                    inv2 : Movement
                    inv2 =
                        movement "inv-2" SupplierInvoiceMovement "supplier" USD 100 1000 "2026-02-01" Nothing

                    payment : Movement
                    payment =
                        movement "pay-1" ExpenseMovement "supplier" USD 250 1000 "2026-03-01" (intent [ "inv-2", "inv-1" ])

                    allocations : List InvoiceAllocation.Allocation
                    allocations =
                        InvoiceAllocation.allocate [ inv2, payment, inv1 ]
                in
                Expect.all
                    [ \_ -> Expect.equal 3 (List.length allocations)
                    , \_ -> Expect.equal [ "inv-1", "inv-2", "inv-1" ] (List.map .targetMovementId allocations)
                    , \_ -> Expect.equal [ 100, 100, 50 ] (List.map .amountInTargetCurrency allocations)
                    , \_ -> Expect.equal OverSettled (InvoiceAllocation.invoiceSettlementFor allocations inv1).status
                    , \_ -> Expect.within (Expect.Absolute 0.0001) -50 (InvoiceAllocation.invoiceSettlementFor allocations inv1).remainingDue
                    , \_ -> Expect.equal FullySettled (InvoiceAllocation.invoiceSettlementFor allocations inv2).status
                    ]
                    ()
        , test "allocates ARS payment to USD invoice using the payment exchange rate" <|
            \_ ->
                let
                    invoice : Movement
                    invoice =
                        movement "inv-usd" SupplierInvoiceMovement "supplier" USD 100 1485 "2026-01-01" Nothing

                    payment : Movement
                    payment =
                        movement "pay-ars" ExpenseMovement "supplier" ARS 148500 1485 "2026-01-02" (intent [ "inv-usd" ])

                    allocations : List InvoiceAllocation.Allocation
                    allocations =
                        InvoiceAllocation.allocate [ invoice, payment ]
                in
                case allocations of
                    [ allocation ] ->
                        Expect.all
                            [ \actual -> Expect.equal ExpenseToInvoice actual.kind
                            , \actual -> Expect.within (Expect.Absolute 0.0001) 148500 actual.amountInSourceCurrency
                            , \actual -> Expect.within (Expect.Absolute 0.0001) 100 actual.amountInTargetCurrency
                            , \_ -> Expect.equal FullySettled (InvoiceAllocation.invoiceSettlementFor allocations invoice).status
                            ]
                            allocation

                    _ ->
                        Expect.fail "Expected one allocation"
        , test "does not allocate across accounts" <|
            \_ ->
                let
                    invoice : Movement
                    invoice =
                        movement "inv-1" SupplierInvoiceMovement "supplier-a" USD 100 1000 "2026-01-01" Nothing

                    payment : Movement
                    payment =
                        movement "pay-1" ExpenseMovement "supplier-b" USD 100 1000 "2026-01-02" (intent [ "inv-1" ])
                in
                InvoiceAllocation.allocate [ invoice, payment ]
                    |> Expect.equal []
        , test "credit note offsets an already paid invoice and creates overpayment" <|
            \_ ->
                let
                    invoice : Movement
                    invoice =
                        movement "inv-1" SupplierInvoiceMovement "supplier" USD 1000 1000 "2026-01-01" Nothing

                    payment : Movement
                    payment =
                        movement "pay-1" ExpenseMovement "supplier" USD 1000 1000 "2026-01-02" (intent [ "inv-1" ])

                    creditNote : Movement
                    creditNote =
                        movement "cn-1" SupplierCreditNoteMovement "supplier" USD 200 1000 "2026-01-03" (intent [ "inv-1" ])

                    allocations : List InvoiceAllocation.Allocation
                    allocations =
                        InvoiceAllocation.allocate [ invoice, payment, creditNote ]
                in
                Expect.all
                    [ \_ -> Expect.equal OverSettled (InvoiceAllocation.invoiceSettlementFor allocations invoice).status
                    , \_ -> Expect.within (Expect.Absolute 0.0001) -200 (InvoiceAllocation.invoiceSettlementFor allocations invoice).remainingDue
                    , \_ -> Expect.equal FullySettled (InvoiceAllocation.creditNoteSettlementFor allocations creditNote).status
                    ]
                    ()
        , test "refund income allocated to credit note reduces its invoice offset" <|
            \_ ->
                let
                    invoice : Movement
                    invoice =
                        movement "inv-1" SupplierInvoiceMovement "supplier" USD 1000 1000 "2026-01-01" Nothing

                    payment : Movement
                    payment =
                        movement "pay-1" ExpenseMovement "supplier" USD 1000 1000 "2026-01-02" (intent [ "inv-1" ])

                    creditNote : Movement
                    creditNote =
                        movement "cn-1" SupplierCreditNoteMovement "supplier" USD 200 1000 "2026-01-03" (intent [ "inv-1" ])

                    refund : Movement
                    refund =
                        movement "refund-1" IncomeMovement "supplier" USD 200 1000 "2026-01-04" (intent [ "cn-1" ])

                    allocations : List InvoiceAllocation.Allocation
                    allocations =
                        InvoiceAllocation.allocate [ invoice, payment, creditNote, refund ]
                in
                Expect.all
                    [ \_ -> Expect.equal FullySettled (InvoiceAllocation.invoiceSettlementFor allocations invoice).status
                    , \_ -> Expect.within (Expect.Absolute 0.0001) 0 (InvoiceAllocation.invoiceSettlementFor allocations invoice).remainingDue
                    , \_ -> Expect.equal FullySettled (InvoiceAllocation.creditNoteSettlementFor allocations creditNote).status
                    , \_ -> Expect.equal [ IncomeToCreditNote, ExpenseToInvoice ] (List.map .kind allocations)
                    ]
                    ()
        , test "credit note only offsets same-currency invoices" <|
            \_ ->
                let
                    invoice : Movement
                    invoice =
                        movement "inv-ars" SupplierInvoiceMovement "supplier" ARS 100000 1000 "2026-01-01" Nothing

                    creditNote : Movement
                    creditNote =
                        movement "cn-usd" SupplierCreditNoteMovement "supplier" USD 100 1000 "2026-01-02" (intent [ "inv-ars" ])
                in
                InvoiceAllocation.allocate [ invoice, creditNote ]
                    |> Expect.equal []
        ]


intent : List String -> Maybe AllocationIntent
intent targetIds =
    Just
        { targetIds = targetIds
        , targetSelectionSource = UserSelectedTargets
        , strategy = OldestDueFirstThenOverpayOldest
        }


movement : String -> MovementType -> String -> Currency -> Float -> Float -> String -> Maybe AllocationIntent -> Movement
movement id movementType accountId currency amount exchangeRate date allocationIntent =
    let
        converted : { ars : Float, usd : Float }
        converted =
            Accounting.cashflowFor movementType exchangeRate currency amount
    in
    { id = id
    , movementType = movementType
    , description = Nothing
    , accountId = accountId
    , accountName = accountId
    , inputAmount = amount
    , inputCurrency = currency
    , exchangeRate = exchangeRate
    , ars = converted.ars
    , usd = converted.usd
    , date = date
    , deletedAt = Nothing
    , relatedToInvoice =
        case movementType of
            ExpenseMovement ->
                allocationIntent /= Nothing

            IncomeMovement ->
                allocationIntent /= Nothing

            _ ->
                False
    , documentNumber = Nothing
    , allocationIntent = allocationIntent
    }
