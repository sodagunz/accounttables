module View.MovementForm exposing (Config, view)

import Accounting exposing (Account, Currency(..), Form, Movement, MovementType(..), currencyToString, movementTypeToString)
import Api.Dolar exposing (ExchangeRateStatus(..))
import Html exposing (Html, button, div, input, label, option, p, section, select, span, strong, text)
import Html.Attributes exposing (attribute, autofocus, checked, class, classList, name, step, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import InvoiceReport
import Time
import Util.Date as Date
import Util.Format exposing (formatMoney)


type alias Config msg =
    { form : Form
    , accounts : List Account
    , movements : List Movement
    , exchangeRate : Float
    , exchangeRateStatus : ExchangeRateStatus
    , zone : Time.Zone
    , error : String
    , onDescription : String -> msg
    , onAmount : String -> msg
    , onAccount : String -> msg
    , onCreateAccount : msg
    , onCurrency : String -> msg
    , onDate : String -> msg
    , onMovementType : MovementType -> msg
    , onRelatedToInvoice : Bool -> msg
    , onDocumentNumber : String -> msg
    , onToggleAllocationTarget : String -> Bool -> msg
    , onSubmit : msg
    , onCancel : msg
    }


isInvoiceType : MovementType -> Bool
isInvoiceType movementType =
    movementType == SupplierInvoiceMovement || movementType == SupplierCreditNoteMovement


isCashflowType : MovementType -> Bool
isCashflowType movementType =
    movementType == ExpenseMovement || movementType == IncomeMovement


dateLabel : Form -> String
dateLabel form =
    if isInvoiceType form.movementType then
        "Vencimiento"

    else
        "Fecha"


submitButtonLabel : Form -> String
submitButtonLabel form =
    case form.movementType of
        ExpenseMovement ->
            "Registrar gasto"

        IncomeMovement ->
            "Registrar ingreso"

        SupplierInvoiceMovement ->
            "Registrar factura"

        SupplierCreditNoteMovement ->
            "Registrar nota de crédito"


view : Config msg -> Html msg
view config =
    let
        selectedAccountId : String
        selectedAccountId =
            selectedOrDefaultAccountId config.form.accountId config.accounts

        editing : Bool
        editing =
            config.form.editingId /= Nothing
    in
    section [ class "panel movement-panel" ]
        [ Html.h2 [ class "section-title movement-title" ] [ text "Registrar movimiento" ]
        , Html.form [ class "form-grid", attribute "data-tutorial" "movement-form", onSubmit config.onSubmit ]
            [ label []
                [ text "Importe"
                , input
                    [ class "amount-input"
                    , type_ "number"
                    , attribute "inputmode" "decimal"
                    , attribute "autocomplete" "off"
                    , attribute "aria-label" "Importe del movimiento"
                    , attribute "min" "0.01"
                    , step "0.01"
                    , attribute "data-tutorial" "movement-amount"
                    , autofocus True
                    , value config.form.amount
                    , onInput config.onAmount
                    ]
                    []
                ]
            , div [ class "movement-type" ]
                [ span [ class "movement-type__label" ] [ text "Tipo" ]
                , label
                    [ class "movement-type__option"
                    , classList [ ( "movement-type__option--active", config.form.movementType == ExpenseMovement ) ]
                    ]
                    [ input
                        [ type_ "radio"
                        , name "movement-type"
                        , value (movementTypeToString ExpenseMovement)
                        , checked (config.form.movementType == ExpenseMovement)
                        , onClick (config.onMovementType ExpenseMovement)
                        ]
                        []
                    , span [] [ text "Gasto" ]
                    ]
                , label
                    [ class "movement-type__option"
                    , classList [ ( "movement-type__option--active", config.form.movementType == IncomeMovement ) ]
                    ]
                    [ input
                        [ type_ "radio"
                        , name "movement-type"
                        , value (movementTypeToString IncomeMovement)
                        , checked (config.form.movementType == IncomeMovement)
                        , onClick (config.onMovementType IncomeMovement)
                        ]
                        []
                    , span [] [ text "Ingreso" ]
                    ]
                , label
                    [ class "movement-type__option"
                    , classList [ ( "movement-type__option--active", config.form.movementType == SupplierInvoiceMovement ) ]
                    ]
                    [ input
                        [ type_ "radio"
                        , name "movement-type"
                        , value (movementTypeToString SupplierInvoiceMovement)
                        , checked (config.form.movementType == SupplierInvoiceMovement)
                        , onClick (config.onMovementType SupplierInvoiceMovement)
                        ]
                        []
                    , span [] [ text "Factura" ]
                    ]
                , label
                    [ class "movement-type__option"
                    , classList [ ( "movement-type__option--active", config.form.movementType == SupplierCreditNoteMovement ) ]
                    ]
                    [ input
                        [ type_ "radio"
                        , name "movement-type"
                        , value (movementTypeToString SupplierCreditNoteMovement)
                        , checked (config.form.movementType == SupplierCreditNoteMovement)
                        , onClick (config.onMovementType SupplierCreditNoteMovement)
                        ]
                        []
                    , span [] [ text "N. cred." ]
                    ]
                ]
            , if isInvoiceType config.form.movementType then
                label [ class "document-number-field" ]
                    [ text "Número"
                    , input
                        [ class "document-number-field__input"
                        , type_ "text"
                        , value config.form.documentNumber
                        , onInput config.onDocumentNumber
                        ]
                        []
                    ]

              else
                text ""
            , label [ class "description-field" ]
                [ text "Descripción"
                , input [ class "description-field__input", type_ "text", value config.form.description, onInput config.onDescription ] []
                ]
            , label []
                [ text "Cuenta"
                , accountControl config selectedAccountId
                ]
            , div [ class "two-col" ]
                [ label []
                    [ text (dateLabel config.form)
                    , input [ type_ "date", value config.form.date, onInput config.onDate ] []
                    ]
                , label []
                    [ text "Divisa"
                    , select [ value (currencyToString config.form.currency), onInput config.onCurrency ]
                        [ option [ value "ARS" ] [ text "ARS" ]
                        , option [ value "USD" ] [ text "U$D" ]
                        ]
                    ]
                ]
            , if isCashflowType config.form.movementType && not editing then
                label [ class "related-to-invoice-field" ]
                    [ input
                        [ type_ "checkbox"
                        , checked config.form.relatedToInvoice
                        , onClick (config.onRelatedToInvoice (not config.form.relatedToInvoice))
                        ]
                        []
                    , span [] [ text "Relacionado a factura" ]
                    ]

              else
                text ""
            , allocationPicker config selectedAccountId
            , exchangeRateView config
            , p [ class "error" ] [ text config.error ]
            , let
                buttonText : String
                buttonText =
                    if editing then
                        "Guardar cambios"

                    else
                        submitButtonLabel config.form
              in
              button [ class "primary primary--movement", type_ "submit" ] [ text buttonText ]
            , if editing then
                button [ class "cancel-button", type_ "button", onClick config.onCancel ] [ text "Cancelar" ]

              else
                text ""
            ]
        ]


type PickerMode
    = ExpenseInvoiceTargets
    | IncomeCreditNoteTargets
    | CreditNoteInvoiceTargets


allocationPicker : Config msg -> String -> Html msg
allocationPicker config selectedAccountId =
    case pickerMode config.form of
        Nothing ->
            text ""

        Just mode ->
            let
                rows : List InvoiceReport.DocumentRow
                rows =
                    allocationRows config selectedAccountId mode
            in
            div [ class "allocation-picker" ]
                [ div [ class "allocation-picker__header" ]
                    [ strong [] [ text (pickerTitle mode) ]
                    , span [] [ text (pickerHelp mode) ]
                    ]
                , if List.isEmpty rows then
                    p [ class "allocation-picker__empty" ] [ text (pickerEmptyText mode) ]

                  else
                    div [ class "allocation-picker__list" ]
                        (List.map (allocationTargetRow config) rows)
                ]


pickerMode : Form -> Maybe PickerMode
pickerMode form =
    case form.movementType of
        ExpenseMovement ->
            if form.relatedToInvoice then
                Just ExpenseInvoiceTargets

            else
                Nothing

        IncomeMovement ->
            if form.relatedToInvoice then
                Just IncomeCreditNoteTargets

            else
                Nothing

        SupplierCreditNoteMovement ->
            Just CreditNoteInvoiceTargets

        SupplierInvoiceMovement ->
            Nothing


allocationRows : Config msg -> String -> PickerMode -> List InvoiceReport.DocumentRow
allocationRows config selectedAccountId mode =
    let
        candidates : List Movement
        candidates =
            config.movements
                |> List.filter (eligibleAllocationTarget config.form selectedAccountId mode)
                |> List.sortWith compareByDateThenId
    in
    InvoiceReport.build config.movements candidates []
        |> .rows
        |> List.sortWith compareDocumentRowsByDateThenId


eligibleAllocationTarget : Form -> String -> PickerMode -> Movement -> Bool
eligibleAllocationTarget form selectedAccountId mode movement =
    movement.deletedAt
        == Nothing
        && movement.accountId
        == selectedAccountId
        && movement.movementType
        == targetMovementType mode
        && (case mode of
                CreditNoteInvoiceTargets ->
                    movement.inputCurrency == form.currency

                _ ->
                    True
           )


targetMovementType : PickerMode -> MovementType
targetMovementType mode =
    case mode of
        ExpenseInvoiceTargets ->
            SupplierInvoiceMovement

        IncomeCreditNoteTargets ->
            SupplierCreditNoteMovement

        CreditNoteInvoiceTargets ->
            SupplierInvoiceMovement


allocationTargetRow : Config msg -> InvoiceReport.DocumentRow -> Html msg
allocationTargetRow config documentRow =
    let
        movement : Movement
        movement =
            documentRow.movement

        selected : Bool
        selected =
            selectedTargetIds config.form
                |> List.member movement.id
    in
    label
        [ class "allocation-target-row"
        , classList [ ( "allocation-target-row--selected", selected ) ]
        ]
        [ input
            [ type_ "checkbox"
            , checked selected
            , onClick (config.onToggleAllocationTarget movement.id (not selected))
            ]
            []
        , div [ class "allocation-target-row__body" ]
            [ span [ class "allocation-target-row__title" ] [ text (documentTitle movement) ]
            , span [ class "allocation-target-row__meta" ]
                [ text
                    ("Vence "
                        ++ Date.formatDate Date.NumericDate movement.date
                        ++ " · "
                        ++ formatMoney movement.inputCurrency movement.inputAmount
                    )
                ]
            , span [ class "allocation-target-row__meta" ]
                [ text
                    ("Estado: "
                        ++ documentRow.statusLabel
                        ++ " · Pendiente: "
                        ++ formatMoney documentRow.settlement.currency documentRow.settlement.remainingDue
                    )
                ]
            ]
        ]


selectedTargetIds : Form -> List String
selectedTargetIds form =
    form.allocationIntent
        |> Maybe.map .targetIds
        |> Maybe.withDefault []


documentTitle : Movement -> String
documentTitle movement =
    case movement.documentNumber of
        Just number ->
            number

        Nothing ->
            "Sin número"


pickerTitle : PickerMode -> String
pickerTitle mode =
    case mode of
        ExpenseInvoiceTargets ->
            "Facturas a pagar"

        IncomeCreditNoteTargets ->
            "Notas de crédito a cobrar"

        CreditNoteInvoiceTargets ->
            "Facturas a compensar"


pickerHelp : PickerMode -> String
pickerHelp mode =
    case mode of
        ExpenseInvoiceTargets ->
            "Selecciona una o más facturas de esta cuenta."

        IncomeCreditNoteTargets ->
            "Selecciona una o más notas de crédito de esta cuenta."

        CreditNoteInvoiceTargets ->
            "Selecciona facturas de esta cuenta y divisa para aplicar la nota."


pickerEmptyText : PickerMode -> String
pickerEmptyText mode =
    case mode of
        ExpenseInvoiceTargets ->
            "No hay facturas en esta cuenta para seleccionar."

        IncomeCreditNoteTargets ->
            "No hay notas de crédito en esta cuenta para seleccionar."

        CreditNoteInvoiceTargets ->
            "No hay facturas de esta cuenta y divisa para compensar."


compareDocumentRowsByDateThenId : InvoiceReport.DocumentRow -> InvoiceReport.DocumentRow -> Order
compareDocumentRowsByDateThenId left right =
    compareByDateThenId left.movement right.movement


compareByDateThenId : Movement -> Movement -> Order
compareByDateThenId left right =
    case compare left.date right.date of
        EQ ->
            compare left.id right.id

        order ->
            order


selectedOrDefaultAccountId : String -> List Account -> String
selectedOrDefaultAccountId selectedAccountId accounts =
    if List.any (\account -> account.id == selectedAccountId) accounts then
        selectedAccountId

    else
        accounts
            |> List.head
            |> Maybe.map .id
            |> Maybe.withDefault ""


createAccountValue : String
createAccountValue =
    "__create_account__"


accountControl : Config msg -> String -> Html msg
accountControl config selectedAccountId =
    case config.accounts of
        [] ->
            button
                [ class "select-action"
                , type_ "button"
                , onClick config.onCreateAccount
                ]
                [ text "Agregar una cuenta" ]

        _ ->
            select
                [ value selectedAccountId
                , onInput
                    (\value ->
                        if value == createAccountValue then
                            config.onCreateAccount

                        else
                            config.onAccount value
                    )
                ]
                (List.map accountOption config.accounts
                    ++ [ option [ value createAccountValue ] [ text "Agregar una cuenta" ] ]
                )


accountOption : Account -> Html msg
accountOption account =
    option [ value account.id ] [ text account.name ]


exchangeRateView : Config msg -> Html msg
exchangeRateView config =
    let
        status : String
        status =
            case config.exchangeRateStatus of
                LoadingRate ->
                    "Cargando cotización oficial..."

                LoadedRate updatedAt ->
                    "Actualizado: " ++ Date.formatApiDate config.zone updatedAt

                FailedRate ->
                    "No se pudo cargar DolarApi. Usando cotización de respaldo."
    in
    div [ class "rate-status" ]
        [ p []
            [ strong [] [ text "1 U$D = " ]
            , strong [] [ text (formatMoney ARS config.exchangeRate) ]
            ]
        , p [ class "rate-status__meta" ] [ text status ]
        ]
