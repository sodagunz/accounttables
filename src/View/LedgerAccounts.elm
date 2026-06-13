module View.LedgerAccounts exposing (Config, view)

import Accounting exposing (Account)
import Html exposing (Html, button, div, input, li, p, section, text, ul)
import Html.Attributes exposing (class, placeholder, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)


type alias Config msg =
    { accounts : List Account
    , newAccountName : String
    , error : String
    , onName : String -> msg
    , onAdd : msg
    , onDelete : String -> msg
    }


view : Config msg -> Html msg
view config =
    section [ class "panel accounts-panel" ]
        [ Html.h2 [ class "section-title" ] [ text "Cajas" ]
        , Html.form [ class "inline-form", onSubmit config.onAdd ]
            [ input
                [ type_ "text"
                , placeholder "Caja"
                , value config.newAccountName
                , onInput config.onName
                ]
                []
            , button [ class "primary", type_ "submit" ] [ text "Agregar" ]
            ]
        , p [ class "error" ] [ text config.error ]
        , if List.isEmpty config.accounts then
            p [ class "empty empty--compact" ] [ text "No hay cajas activas." ]

          else
            ul [ class "account-list" ] (List.map (accountRow config) config.accounts)
        ]


accountRow : Config msg -> Account -> Html msg
accountRow config account =
    li [ class "account-list__item" ]
        [ div [] [ text account.name ]
        , button
            [ type_ "button"
            , class "danger-button"
            , onClick (config.onDelete account.id)
            ]
            [ text "Eliminar" ]
        ]
