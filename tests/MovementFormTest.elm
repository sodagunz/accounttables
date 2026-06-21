module MovementFormTest exposing (suite)

import Accounting exposing (Account, Currency(..), Form, Movement, MovementType(..))
import Allocation exposing (AllocationIntent)
import Expect
import Test exposing (Test, describe, test)
import View.MovementForm


suite : Test
suite =
    describe "MovementForm"
        [ test "shows no eligible invoice warning for related expense with no candidates" <|
            \_ ->
                View.MovementForm.preSaveWarning 1000 [ sampleAccount ] [] relatedExpenseForm
                    |> Expect.equal
                        (Just "Este pago está marcado para aplicarse a facturas, pero no hay facturas elegibles en esta cuenta. Puedes guardarlo, pero no quedará aplicado a ninguna factura.")
        , test "shows overpayment warning for related expense when selected invoices are below the payment amount" <|
            \_ ->
                let
                    form : Form
                    form =
                        relatedExpenseForm
                            |> Accounting.setAmount "150"
                            |> Accounting.toggleAllocationTarget "inv-1" True
                in
                View.MovementForm.preSaveWarning 1000 [ sampleAccount ] [ usdInvoice "inv-1" 100 ] form
                    |> Expect.equal
                        (Just "Estás pagando más de lo pendiente en las facturas seleccionadas. El sobrante quedará como sobrepago en la factura más antigua seleccionada.")
        , test "shows insufficient payment warning for related expense when selected invoices exceed the payment amount" <|
            \_ ->
                let
                    form : Form
                    form =
                        relatedExpenseForm
                            |> Accounting.setAmount "50"
                            |> Accounting.toggleAllocationTarget "inv-1" True
                in
                View.MovementForm.preSaveWarning 1000 [ sampleAccount ] [ usdInvoice "inv-1" 100 ] form
                    |> Expect.equal
                        (Just "El pago no alcanza para cubrir todas las facturas seleccionadas. Se aplicará primero a las más antiguas y quedará saldo pendiente.")
        , test "shows insufficient credit-note warning when selected invoices exceed the note amount" <|
            \_ ->
                let
                    form : Form
                    form =
                        creditNoteForm
                            |> Accounting.setAmount "40"
                            |> Accounting.toggleAllocationTarget "inv-1" True
                in
                View.MovementForm.preSaveWarning 1000 [ sampleAccount ] [ usdInvoice "inv-1" 100 ] form
                    |> Expect.equal
                        (Just "La nota de crédito no alcanza para compensar todas las facturas seleccionadas. Se aplicará primero a las más antiguas y quedará saldo pendiente.")
        , test "shows no warning for exact auto-target match" <|
            \_ ->
                View.MovementForm.preSaveWarning 1000 [ sampleAccount ] [ usdInvoice "inv-1" 100 ] relatedExpenseForm
                    |> Expect.equal Nothing
        , test "hides exchange-rate display for invoice-like forms only" <|
            \_ ->
                Expect.all
                    [ \_ -> Expect.equal True (View.MovementForm.showsExchangeRate relatedExpenseForm)
                    , \_ -> Expect.equal False (View.MovementForm.showsExchangeRate { creditNoteForm | movementType = SupplierInvoiceMovement })
                    , \_ -> Expect.equal False (View.MovementForm.showsExchangeRate creditNoteForm)
                    ]
                    ()
        ]


sampleAccount : Account
sampleAccount =
    { id = "supplier", name = "Proveedor", deletedAt = Nothing }


relatedExpenseForm : Form
relatedExpenseForm =
    { baseForm
        | amount = "100"
        , accountId = sampleAccount.id
        , currency = USD
        , date = "2026-06-20"
        , movementType = ExpenseMovement
        , relatedToInvoice = True
    }


creditNoteForm : Form
creditNoteForm =
    { baseForm
        | amount = "100"
        , accountId = sampleAccount.id
        , currency = USD
        , date = "2026-06-20"
        , movementType = SupplierCreditNoteMovement
        , documentNumber = "NC-001"
    }


baseForm : Form
baseForm =
    Accounting.emptyForm


usdInvoice : String -> Float -> Movement
usdInvoice id amount =
    movement id SupplierInvoiceMovement USD amount Nothing


movement : String -> MovementType -> Currency -> Float -> Maybe AllocationIntent -> Movement
movement id movementType currency amount allocationIntent =
    let
        converted : { ars : Float, usd : Float }
        converted =
            Accounting.cashflowFor movementType 1000 currency amount
    in
    { id = id
    , movementType = movementType
    , description = Nothing
    , accountId = sampleAccount.id
    , accountName = sampleAccount.name
    , inputAmount = amount
    , inputCurrency = currency
    , exchangeRate = 1000
    , ars = converted.ars
    , usd = converted.usd
    , date = "2026-06-16"
    , deletedAt = Nothing
    , relatedToInvoice =
        case movementType of
            ExpenseMovement ->
                allocationIntent /= Nothing

            IncomeMovement ->
                allocationIntent /= Nothing

            _ ->
                False
    , documentNumber = Just id
    , allocationIntent = allocationIntent
    }
