module InvoiceReport exposing
    ( DocumentRow
    , Report
    , Summary
    , build
    )

import Accounting exposing (Currency(..), MoneyTotal, Movement, MovementType(..), invoiceTotal, negateMoney, summarizeMoney)
import InvoiceAllocation exposing (Allocation, AllocationKind(..), DocumentSettlement, DocumentStatus(..))


type alias DocumentRow =
    { movement : Movement
    , settlement : DocumentSettlement
    , statusLabel : String
    , remainingTotal : MoneyTotal
    }


type alias Summary =
    { facturasTotal : MoneyTotal
    , creditNotesTotal : MoneyTotal
    , documentsTotal : MoneyTotal
    , settlementContribution : MoneyTotal
    , payable : MoneyTotal
    , settlementContributionLabel : String
    , usesAllocation : Bool
    }


type alias Report =
    { rows : List DocumentRow
    , allocations : List Allocation
    , summary : Summary
    }


build : List Movement -> List Movement -> List Movement -> Report
build allMovements displayedDocuments displayedRelatedCashflows =
    let
        allocations : List Allocation
        allocations =
            InvoiceAllocation.allocate allMovements

        rows : List DocumentRow
        rows =
            List.map (documentRow allocations) displayedDocuments

        usesAllocation : Bool
        usesAllocation =
            List.any hasAllocationIntent allMovements
    in
    { rows = rows
    , allocations = allocations
    , summary = summaryFor usesAllocation rows displayedDocuments displayedRelatedCashflows
    }


hasAllocationIntent : Movement -> Bool
hasAllocationIntent movement =
    movement.allocationIntent /= Nothing


documentRow : List Allocation -> Movement -> DocumentRow
documentRow allocations movement =
    let
        settlement : DocumentSettlement
        settlement =
            settlementFor allocations movement
    in
    { movement = movement
    , settlement = settlement
    , statusLabel = statusLabelFor allocations movement settlement.status
    , remainingTotal = signedRemainingTotal movement settlement
    }


settlementFor : List Allocation -> Movement -> DocumentSettlement
settlementFor allocations movement =
    case movement.movementType of
        SupplierInvoiceMovement ->
            InvoiceAllocation.invoiceSettlementFor allocations movement

        SupplierCreditNoteMovement ->
            InvoiceAllocation.creditNoteSettlementFor allocations movement

        _ ->
            InvoiceAllocation.invoiceSettlementFor allocations movement


statusLabelFor : List Allocation -> Movement -> DocumentStatus -> String
statusLabelFor allocations movement status =
    case movement.movementType of
        SupplierInvoiceMovement ->
            invoiceStatusLabel status

        SupplierCreditNoteMovement ->
            creditNoteStatusLabel (hasRefundAllocation allocations movement.id) status

        _ ->
            ""


invoiceStatusLabel : DocumentStatus -> String
invoiceStatusLabel status =
    case status of
        Pending ->
            "Pendiente"

        PartiallySettled ->
            "Parcialmente pagada"

        FullySettled ->
            "Pagada"

        OverSettled ->
            "Sobrepagada"


creditNoteStatusLabel : Bool -> DocumentStatus -> String
creditNoteStatusLabel hasRefund status =
    case status of
        Pending ->
            "Pendiente"

        PartiallySettled ->
            if hasRefund then
                "Parcialmente reembolsada"

            else
                "Parcialmente aplicada"

        FullySettled ->
            if hasRefund then
                "Reembolsada"

            else
                "Aplicada"

        OverSettled ->
            if hasRefund then
                "Reembolsada en exceso"

            else
                "Aplicada en exceso"


hasRefundAllocation : List Allocation -> String -> Bool
hasRefundAllocation allocations creditNoteId =
    List.any
        (\allocation -> allocation.kind == IncomeToCreditNote && allocation.targetMovementId == creditNoteId)
        allocations


summaryFor : Bool -> List DocumentRow -> List Movement -> List Movement -> Summary
summaryFor usesAllocation rows displayedDocuments displayedRelatedCashflows =
    let
        facturasTotal : MoneyTotal
        facturasTotal =
            displayedDocuments
                |> List.filter (\m -> m.movementType == SupplierInvoiceMovement)
                |> summarizeMoney

        creditNotesTotal : MoneyTotal
        creditNotesTotal =
            displayedDocuments
                |> List.filter (\m -> m.movementType == SupplierCreditNoteMovement)
                |> summarizeMoney

        documentsTotal : MoneyTotal
        documentsTotal =
            summarizeMoney displayedDocuments

        payable : MoneyTotal
        payable =
            if usesAllocation then
                sumMoney (List.map .remainingTotal rows)

            else
                invoiceTotal displayedDocuments displayedRelatedCashflows

        settlementContribution : MoneyTotal
        settlementContribution =
            if usesAllocation then
                subtractMoney payable documentsTotal

            else
                displayedRelatedCashflows
                    |> summarizeMoney
                    |> negateMoney
    in
    { facturasTotal = facturasTotal
    , creditNotesTotal = creditNotesTotal
    , documentsTotal = documentsTotal
    , settlementContribution = settlementContribution
    , payable = payable
    , settlementContributionLabel =
        if usesAllocation then
            "Aplicaciones y cobros"

        else
            "Movimientos relacionados"
    , usesAllocation = usesAllocation
    }


signedRemainingTotal : Movement -> DocumentSettlement -> MoneyTotal
signedRemainingTotal movement settlement =
    let
        converted : MoneyTotal
        converted =
            convert movement.exchangeRate settlement.currency settlement.remainingDue

        sign : Float
        sign =
            case movement.movementType of
                SupplierInvoiceMovement ->
                    -1

                SupplierCreditNoteMovement ->
                    1

                _ ->
                    1
    in
    scaleMoney sign converted


convert : Float -> Currency -> Float -> MoneyTotal
convert exchangeRate currency amount =
    case currency of
        ARS ->
            { ars = amount, usd = amount / exchangeRate }

        USD ->
            { ars = amount * exchangeRate, usd = amount }


sumMoney : List MoneyTotal -> MoneyTotal
sumMoney totals =
    List.foldl addMoney { ars = 0, usd = 0 } totals


addMoney : MoneyTotal -> MoneyTotal -> MoneyTotal
addMoney left right =
    { ars = left.ars + right.ars
    , usd = left.usd + right.usd
    }


subtractMoney : MoneyTotal -> MoneyTotal -> MoneyTotal
subtractMoney left right =
    { ars = left.ars - right.ars
    , usd = left.usd - right.usd
    }


scaleMoney : Float -> MoneyTotal -> MoneyTotal
scaleMoney multiplier total =
    { ars = multiplier * total.ars
    , usd = multiplier * total.usd
    }
