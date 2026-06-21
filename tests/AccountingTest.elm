module AccountingTest exposing (suite)

import Accounting exposing (Account, Currency(..), Form, MovementType(..))
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Accounting"
        [ test "converts USD expenses into negative ARS and USD cashflow" <|
            \_ ->
                Accounting.cashflowFor ExpenseMovement 1000 USD 2
                    |> Expect.equal { ars = -2000, usd = -2 }
        , test "cashflowFor SupplierInvoiceMovement returns negative" <|
            \_ ->
                Accounting.cashflowFor SupplierInvoiceMovement 1000 ARS 100
                    |> Expect.equal { ars = -100, usd = -0.1 }
        , test "cashflowFor SupplierCreditNoteMovement returns positive" <|
            \_ ->
                Accounting.cashflowFor SupplierCreditNoteMovement 1000 ARS 100
                    |> Expect.equal { ars = 100, usd = 0.1 }
        , test "builds an income movement from a valid form" <|
            \_ ->
                let
                    form : Form
                    form =
                        { description = "  Venta  "
                        , amount = "1500"
                        , accountId = "cash"
                        , currency = ARS
                        , date = "2026-06-16"
                        , movementType = IncomeMovement
                        , editingId = Nothing
                        , relatedToInvoice = False
                        , documentNumber = ""
                        }

                    accounts : List Account
                    accounts =
                        [ { id = "cash", name = "Caja", deletedAt = Nothing } ]
                in
                case Accounting.buildMovement 1000 "movement-1" accounts form of
                    Ok movement ->
                        Expect.all
                            [ \actual -> Expect.equal "movement-1" actual.id
                            , \actual -> Expect.equal (Just "Venta") actual.description
                            , \actual -> Expect.equal "cash" actual.accountId
                            , \actual -> Expect.within (Expect.Absolute 0.0001) 1500 actual.ars
                            , \actual -> Expect.within (Expect.Absolute 0.0001) 1.5 actual.usd
                            , \actual -> Expect.equal IncomeMovement actual.movementType
                            , \actual -> Expect.equal False actual.relatedToInvoice
                            , \actual -> Expect.equal Nothing actual.documentNumber
                            ]
                            movement

                    Err error ->
                        Expect.fail error
        , test "buildMovement sets relatedToInvoice True for income when selected" <|
            \_ ->
                let
                    form : Form
                    form =
                        { description = ""
                        , amount = "500"
                        , accountId = "cash"
                        , currency = ARS
                        , date = "2026-06-16"
                        , movementType = IncomeMovement
                        , editingId = Nothing
                        , relatedToInvoice = True
                        , documentNumber = ""
                        }

                    accounts : List Account
                    accounts =
                        [ { id = "cash", name = "Caja", deletedAt = Nothing } ]
                in
                case Accounting.buildMovement 1000 "m2" accounts form of
                    Ok movement ->
                        Expect.equal True movement.relatedToInvoice

                    Err error ->
                        Expect.fail error
        , test "buildMovement forces relatedToInvoice False for SupplierInvoiceMovement" <|
            \_ ->
                let
                    form : Form
                    form =
                        { description = ""
                        , amount = "500"
                        , accountId = "cash"
                        , currency = ARS
                        , date = "2026-06-16"
                        , movementType = SupplierInvoiceMovement
                        , editingId = Nothing
                        , relatedToInvoice = True
                        , documentNumber = "  ABC-123  "
                        }

                    accounts : List Account
                    accounts =
                        [ { id = "cash", name = "Caja", deletedAt = Nothing } ]
                in
                case Accounting.buildMovement 1000 "m3" accounts form of
                    Ok movement ->
                        Expect.all
                            [ \m -> Expect.equal False m.relatedToInvoice
                            , \m -> Expect.equal (Just "ABC-123") m.documentNumber
                            ]
                            movement

                    Err error ->
                        Expect.fail error
        , test "buildMovement forces documentNumber Nothing for ExpenseMovement" <|
            \_ ->
                let
                    form : Form
                    form =
                        { description = ""
                        , amount = "300"
                        , accountId = "cash"
                        , currency = ARS
                        , date = "2026-06-16"
                        , movementType = ExpenseMovement
                        , editingId = Nothing
                        , relatedToInvoice = False
                        , documentNumber = "should-be-ignored"
                        }

                    accounts : List Account
                    accounts =
                        [ { id = "cash", name = "Caja", deletedAt = Nothing } ]
                in
                case Accounting.buildMovement 1000 "m4" accounts form of
                    Ok movement ->
                        Expect.equal Nothing movement.documentNumber

                    Err error ->
                        Expect.fail error
        , test "buildMovement trims and stores documentNumber for SupplierCreditNoteMovement" <|
            \_ ->
                let
                    form : Form
                    form =
                        { description = ""
                        , amount = "200"
                        , accountId = "cash"
                        , currency = ARS
                        , date = "2026-06-16"
                        , movementType = SupplierCreditNoteMovement
                        , editingId = Nothing
                        , relatedToInvoice = False
                        , documentNumber = "  NC-001  "
                        }

                    accounts : List Account
                    accounts =
                        [ { id = "cash", name = "Caja", deletedAt = Nothing } ]
                in
                case Accounting.buildMovement 1000 "m5" accounts form of
                    Ok movement ->
                        Expect.equal (Just "NC-001") movement.documentNumber

                    Err error ->
                        Expect.fail error
        , test "buildMovement stores Nothing when documentNumber is empty for invoice type" <|
            \_ ->
                let
                    form : Form
                    form =
                        { description = ""
                        , amount = "200"
                        , accountId = "cash"
                        , currency = ARS
                        , date = "2026-06-16"
                        , movementType = SupplierInvoiceMovement
                        , editingId = Nothing
                        , relatedToInvoice = False
                        , documentNumber = "  "
                        }

                    accounts : List Account
                    accounts =
                        [ { id = "cash", name = "Caja", deletedAt = Nothing } ]
                in
                case Accounting.buildMovement 1000 "m6" accounts form of
                    Ok movement ->
                        Expect.equal Nothing movement.documentNumber

                    Err error ->
                        Expect.fail error
        , test "rejects a deleted selected account" <|
            \_ ->
                let
                    form : Form
                    form =
                        { description = "Pago"
                        , amount = "10"
                        , accountId = "deleted"
                        , currency = ARS
                        , date = "2026-06-16"
                        , movementType = ExpenseMovement
                        , editingId = Nothing
                        , relatedToInvoice = False
                        , documentNumber = ""
                        }

                    accounts : List Account
                    accounts =
                        [ { id = "deleted", name = "Vieja", deletedAt = Just "deleted" } ]
                in
                Accounting.buildMovement 1000 "movement-1" accounts form
                    |> Expect.equal (Err "Selecciona una cuenta.")
        , test "movementTypeFromString round-trips SupplierInvoice" <|
            \_ ->
                Accounting.movementTypeToString SupplierInvoiceMovement
                    |> Accounting.movementTypeFromString
                    |> Expect.equal SupplierInvoiceMovement
        , test "movementTypeFromString round-trips SupplierCreditNote" <|
            \_ ->
                Accounting.movementTypeToString SupplierCreditNoteMovement
                    |> Accounting.movementTypeFromString
                    |> Expect.equal SupplierCreditNoteMovement
        , test "movementTypeFromString falls back to ExpenseMovement for unknown" <|
            \_ ->
                Accounting.movementTypeFromString "UnknownType"
                    |> Expect.equal ExpenseMovement
        , test "isCashflowMovement returns True for ExpenseMovement" <|
            \_ ->
                let
                    movement : Accounting.Movement
                    movement =
                        { id = "1"
                        , movementType = ExpenseMovement
                        , description = Nothing
                        , accountId = "a"
                        , accountName = "A"
                        , inputAmount = 100
                        , inputCurrency = ARS
                        , exchangeRate = 1000
                        , ars = -100
                        , usd = -0.1
                        , date = "2026-06-16"
                        , deletedAt = Nothing
                        , relatedToInvoice = False
                        , documentNumber = Nothing
                        }
                in
                Accounting.isCashflowMovement movement
                    |> Expect.equal True
        , test "isInvoiceMovement returns True for SupplierInvoiceMovement" <|
            \_ ->
                let
                    movement : Accounting.Movement
                    movement =
                        { id = "2"
                        , movementType = SupplierInvoiceMovement
                        , description = Nothing
                        , accountId = "a"
                        , accountName = "A"
                        , inputAmount = 100
                        , inputCurrency = ARS
                        , exchangeRate = 1000
                        , ars = -100
                        , usd = -0.1
                        , date = "2026-06-16"
                        , deletedAt = Nothing
                        , relatedToInvoice = False
                        , documentNumber = Nothing
                        }
                in
                Accounting.isInvoiceMovement movement
                    |> Expect.equal True
        , test "isInvoiceRelatedCashflow returns True for cashflow with relatedToInvoice" <|
            \_ ->
                let
                    movement : Accounting.Movement
                    movement =
                        { id = "3"
                        , movementType = ExpenseMovement
                        , description = Nothing
                        , accountId = "a"
                        , accountName = "A"
                        , inputAmount = 100
                        , inputCurrency = ARS
                        , exchangeRate = 1000
                        , ars = -100
                        , usd = -0.1
                        , date = "2026-06-16"
                        , deletedAt = Nothing
                        , relatedToInvoice = True
                        , documentNumber = Nothing
                        }
                in
                Accounting.isInvoiceRelatedCashflow movement
                    |> Expect.equal True
        , test "invoiceTotal computes correct payable" <|
            \_ ->
                let
                    invoice : Accounting.Movement
                    invoice =
                        { id = "f1"
                        , movementType = SupplierInvoiceMovement
                        , description = Nothing
                        , accountId = "a"
                        , accountName = "A"
                        , inputAmount = 100
                        , inputCurrency = ARS
                        , exchangeRate = 1000
                        , ars = -100
                        , usd = -0.1
                        , date = "2026-06-16"
                        , deletedAt = Nothing
                        , relatedToInvoice = False
                        , documentNumber = Nothing
                        }

                    payment : Accounting.Movement
                    payment =
                        { id = "p1"
                        , movementType = ExpenseMovement
                        , description = Nothing
                        , accountId = "a"
                        , accountName = "A"
                        , inputAmount = 40
                        , inputCurrency = ARS
                        , exchangeRate = 1000
                        , ars = -40
                        , usd = -0.04
                        , date = "2026-06-16"
                        , deletedAt = Nothing
                        , relatedToInvoice = True
                        , documentNumber = Nothing
                        }
                in
                Accounting.invoiceTotal [ invoice ] [ payment ]
                    |> Expect.all
                        [ \total -> Expect.within (Expect.Absolute 0.00001) -60 total.ars
                        , \total -> Expect.within (Expect.Absolute 0.00001) -0.06 total.usd
                        ]
        ]
