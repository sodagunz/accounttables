module View.MovementForm exposing (Config, view)

import Accounting exposing (Account, Currency(..), Form, MovementType(..), currencyToString, movementTypeToString)
import Api.Dolar exposing (ExchangeRateStatus(..))
import Html exposing (Html, button, div, input, label, option, p, section, select, span, strong, text)
import Html.Attributes exposing (attribute, autofocus, checked, class, classList, name, step, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Time
import Util.Date as Date
import Util.Format exposing (formatMoney)


type alias Config msg =
    { form : Form
    , accounts : List Account
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
                    , span [] [ text "Nota de crédito" ]
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
