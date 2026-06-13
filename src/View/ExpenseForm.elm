module View.ExpenseForm exposing (Config, view)

import Accounting exposing (Currency(..), Form, WorkspaceUser, convert, currencyToString)
import Api.Dolar exposing (ExchangeRateStatus(..))
import Html exposing (Html, button, div, input, label, option, p, section, select, strong, text)
import Html.Attributes exposing (class, step, type_, value)
import Html.Events exposing (onInput, onSubmit)
import Time
import Util.Date as Date
import Util.Format exposing (formatMoney)


type alias Config msg =
    { form : Form
    , users : List WorkspaceUser
    , exchangeRate : Float
    , exchangeRateStatus : ExchangeRateStatus
    , zone : Time.Zone
    , error : String
    , onDescription : String -> msg
    , onAmount : String -> msg
    , onPerson : String -> msg
    , onCurrency : String -> msg
    , onDate : String -> msg
    , onSubmit : msg
    }


view : Config msg -> Html msg
view config =
    section [ class "panel" ]
        [ Html.h2 [ class "section-title" ] [ text "Nuevo gasto" ]
        , Html.form [ class "form-grid", onSubmit config.onSubmit ]
            [ label []
                [ text "Descripción"
                , input [ type_ "text", value config.form.description, onInput config.onDescription ] []
                ]
            , div [ class "two-col" ]
                [ label []
                    [ text "Importe"
                    , input [ type_ "number", step "0.01", value config.form.amount, onInput config.onAmount ] []
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
                    [ text "Nombre"
                    , select [ value config.form.userId, onInput config.onPerson ]
                        (userOptions config.users)
                    ]
                , label []
                    [ text "Fecha"
                    , input [ type_ "date", value config.form.date, onInput config.onDate ] []
                    ]
                ]
            , conversionPreview config.exchangeRate config.form
            , exchangeRateView config
            , p [ class "error" ] [ text config.error ]
            , button [ class "primary", type_ "submit" ] [ text "Agregar gasto" ]
            ]
        ]


userOptions : List WorkspaceUser -> List (Html msg)
userOptions users =
    case users of
        [] ->
            [ option [ value "" ] [ text "Agrega una persona" ] ]

        _ ->
            option [ value "" ] [ text "Seleccionar" ]
                :: List.map userOption users


userOption : WorkspaceUser -> Html msg
userOption user =
    option [ value user.id ] [ text user.name ]


conversionPreview : Float -> Form -> Html msg
conversionPreview exchangeRate form =
    case String.toFloat form.amount of
        Nothing ->
            text ""

        Just amount ->
            let
                converted =
                    convert exchangeRate form.currency amount
            in
            div [ class "conversion" ]
                [ text
                    ("Convertido: "
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
