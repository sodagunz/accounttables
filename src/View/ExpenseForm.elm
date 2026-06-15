module View.ExpenseForm exposing (Config, view)

import Accounting exposing (Account, Currency(..), Form, MovementType(..), cashflowFor, currencyToString, movementTypeToString)
import Api.Dolar exposing (ExchangeRateStatus(..))
import Html exposing (Html, button, div, input, label, option, p, section, select, span, strong, text)
import Html.Attributes exposing (attribute, autofocus, checked, class, classList, for, id, name, step, type_, value)
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
    , onSubmit : msg
    , onCancel : msg
    }


view : Config msg -> Html msg
view config =
    let
        selectedAccountId =
            selectedOrDefaultAccountId config.form.accountId config.accounts
    in
    section [ class "panel movement-panel" ]
        [ Html.h2 [ class "section-title movement-title" ] [ text "Registrar movimiento" ]
        , Html.form [ class "form-grid", onSubmit config.onSubmit ]
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
                    , autofocus True
                    , value config.form.amount
                    , onInput config.onAmount
                    ]
                    []
                ]
            , label [ class "description-field" ]
                [ text "Descripción"
                , input [ class "description-field__input", type_ "text", value config.form.description, onInput config.onDescription ] []
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
                ]
            , label []
                [ text "Cuenta"
                , accountControl config selectedAccountId
                ]
            , div [ class "two-col" ]
                [ label []
                    [ text "Fecha"
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
            , case config.form.editingId of
                Just _ ->
                    text ""

                Nothing ->
                    conversionPreview config.exchangeRate config.form
            , exchangeRateView config
            , p [ class "error" ] [ text config.error ]
            , let
                buttonText =
                    case config.form.editingId of
                        Just _ ->
                            "Guardar cambios"

                        Nothing ->
                            case config.form.movementType of
                                ExpenseMovement ->
                                    "Registrar gasto"

                                IncomeMovement ->
                                    "Registrar ingreso"
              in
              button [ class "primary primary--movement", type_ "submit" ] [ text buttonText ]
            , case config.form.editingId of
                Just _ ->
                    button [ class "cancel-button", type_ "button", onClick config.onCancel ] [ text "Cancelar" ]

                Nothing ->
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


conversionPreview : Float -> Form -> Html msg
conversionPreview exchangeRate form =
    case String.toFloat form.amount of
        Nothing ->
            text ""

        Just amount ->
            let
                converted =
                    cashflowFor form.movementType exchangeRate form.currency amount
            in
            div [ class "conversion" ]
                [ text
                    ("Flujo: "
                        ++ formatMoney ARS converted.ars
                        ++ " / "
                        ++ formatMoney USD converted.usd
                    )
                ]


exchangeRateView : Config msg -> Html msg
exchangeRateView config =
    let
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
