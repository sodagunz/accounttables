module View.LedgerAccounts exposing (Config, view)

import Accounting exposing (Account)
import Html exposing (Html, button, div, input, li, p, section, span, strong, text, ul)
import Html.Attributes exposing (attribute, class, id, placeholder, type_, value)
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
    section [ class "admin-section accounts-panel" ]
        [ Html.details [ class "accounts-disclosure", id "accounts-tool" ]
            [ Html.summary [ class "accounts-disclosure__summary" ]
                [ span [] [ text "Crear o eliminar" ]
                , strong [] [ text "Cuentas" ]
                ]
            , div [ class "accounts-disclosure__content" ]
                [ Html.h2 [ class "section-title" ] [ text "Cuentas" ]
                , Html.form [ class "inline-form", attribute "data-tutorial" "account-form", onSubmit config.onAdd ]
                    [ input
                        [ type_ "text"
                        , id "new-account-name"
                        , attribute "data-tutorial" "account-name"
                        , placeholder "Cuenta"
                        , value config.newAccountName
                        , onInput config.onName
                        ]
                        []
                    , button [ class "primary", type_ "submit" ] [ text "Agregar" ]
                    ]
                , p [ class "error" ] [ text config.error ]
                , if List.isEmpty config.accounts then
                    p [ class "empty empty--compact" ] [ text "No hay cuentas activas." ]

                  else
                    ul [ class "account-list" ] (List.map (accountRow config) config.accounts)
                ]
            ]
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
