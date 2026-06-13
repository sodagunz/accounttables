module View.ExpenseForm exposing (Config, view)

import Accounting exposing (Account, Currency(..), Form, MovementType(..), cashflowFor, currencyToString)
import Api.Dolar exposing (ExchangeRateStatus(..))
import Html exposing (Html, button, div, input, label, option, p, section, select, strong, text)
import Html.Attributes exposing (attribute, autofocus, class, step, type_, value)
import Html.Events exposing (onInput, onSubmit)
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
    , onCurrency : String -> msg
    , onDate : String -> msg
    , onSubmit : msg
    }


view : Config msg -> Html msg
view config =
    section [ class "panel movement-panel" ]
        [ Html.h2 [ class "section-title movement-title" ] [ text "Registrar movimiento" ]
        , Html.form [ class "form-grid", onSubmit config.onSubmit ]
            [ div [ class "two-col" ]
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
                , label []
                    [ text "Divisa"
                    , select [ value (currencyToString config.form.currency), onInput config.onCurrency ]
                        [ option [ value "ARS" ] [ text "AR$" ]
                        , option [ value "USD" ] [ text "U$D" ]
                        ]
                    ]
                ]
            , div [ class "two-col" ]
                [ label []
                    [ text "Caja"
                    , select [ value config.form.accountId, onInput config.onAccount ]
                        (accountOptions config.accounts)
                    ]
                , label []
                    [ text "Fecha"
                    , input [ type_ "date", value config.form.date, onInput config.onDate ] []
                    ]
                ]
            , label [ class "description-field" ]
                [ text "Descripción"
                , input [ class "description-field__input", type_ "text", value config.form.description, onInput config.onDescription ] []
                ]
            , conversionPreview config.exchangeRate config.form
            , exchangeRateView config
            , p [ class "error" ] [ text config.error ]
            , button [ class "primary primary--movement", type_ "submit" ] [ text "Registrar movimiento" ]
            ]
        ]


accountOptions : List Account -> List (Html msg)
accountOptions accounts =
    case accounts of
        [] ->
            [ option [ value "" ] [ text "Agrega una caja" ] ]

        _ ->
            option [ value "" ] [ text "Seleccionar" ]
                :: List.map accountOption accounts


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
                    cashflowFor ExpenseMovement exchangeRate form.currency amount
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
