module InvoiceReportTest exposing (suite)

import Accounting exposing (Currency(..), Movement, MovementType(..))
import Allocation exposing (AllocationIntent, AllocationStrategy(..), TargetSelectionSource(..))
import Expect
import InvoiceReport
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "InvoiceReport"
        [ test "uses ledger-wide allocations for period invoice status and remaining due" <|
            \_ ->
                let
                    invoice : Movement
                    invoice =
                        movement "inv-may" SupplierInvoiceMovement "supplier" USD 100 1000 "2026-05-15" Nothing

                    payment : Movement
                    payment =
                        movement "pay-june" ExpenseMovement "supplier" USD 100 1000 "2026-06-01" (intent [ "inv-may" ])

                    report : InvoiceReport.Report
                    report =
                        InvoiceReport.build [ invoice, payment ] [ invoice ] []
                in
                case report.rows of
                    [ row ] ->
                        Expect.all
                            [ \actual -> Expect.equal "Pagada" actual.statusLabel
                            , \actual -> Expect.within (Expect.Absolute 0.0001) 0 actual.settlement.remainingDue
                            , \_ -> Expect.equal "Aplicaciones y cobros" report.summary.settlementContributionLabel
                            , \_ -> Expect.within (Expect.Absolute 0.0001) 0 report.summary.payable.usd
                            ]
                            row

                    _ ->
                        Expect.fail "Expected one invoice report row"
        , test "keeps legacy aggregate related cashflow summary when there are no allocation intents" <|
            \_ ->
                let
                    invoice : Movement
                    invoice =
                        movement "inv" SupplierInvoiceMovement "supplier" USD 100 1000 "2026-05-15" Nothing

                    payment : Movement
                    payment =
                        { basePayment | relatedToInvoice = True }

                    basePayment : Movement
                    basePayment =
                        movement "pay" ExpenseMovement "supplier" USD 40 1000 "2026-05-20" Nothing

                    report : InvoiceReport.Report
                    report =
                        InvoiceReport.build [ invoice, payment ] [ invoice ] [ payment ]
                in
                Expect.all
                    [ \_ -> Expect.equal "Movimientos relacionados" report.summary.settlementContributionLabel
                    , \_ -> Expect.within (Expect.Absolute 0.0001) -60 report.summary.payable.usd
                    ]
                    ()
        , test "labels credit notes as refunded when refund income allocations exist" <|
            \_ ->
                let
                    invoice : Movement
                    invoice =
                        movement "inv" SupplierInvoiceMovement "supplier" USD 100 1000 "2026-05-15" Nothing

                    creditNote : Movement
                    creditNote =
                        movement "cn" SupplierCreditNoteMovement "supplier" USD 100 1000 "2026-05-16" (intent [ "inv" ])

                    refund : Movement
                    refund =
                        movement "refund" IncomeMovement "supplier" USD 100 1000 "2026-05-17" (intent [ "cn" ])

                    report : InvoiceReport.Report
                    report =
                        InvoiceReport.build [ invoice, creditNote, refund ] [ creditNote ] []
                in
                case report.rows of
                    [ row ] ->
                        Expect.equal "Reembolsada" row.statusLabel

                    _ ->
                        Expect.fail "Expected one credit note report row"
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
