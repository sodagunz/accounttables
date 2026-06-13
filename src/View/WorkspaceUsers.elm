module View.WorkspaceUsers exposing (Config, view)

import Accounting exposing (WorkspaceUser)
import Html exposing (Html, button, div, input, li, p, section, text, ul)
import Html.Attributes exposing (class, placeholder, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)


type alias Config msg =
    { users : List WorkspaceUser
    , newUserName : String
    , error : String
    , onName : String -> msg
    , onAdd : msg
    , onDelete : String -> msg
    }


view : Config msg -> Html msg
view config =
    section [ class "panel users-panel" ]
        [ Html.h2 [ class "section-title" ] [ text "Personas" ]
        , Html.form [ class "user-form", onSubmit config.onAdd ]
            [ input
                [ type_ "text"
                , placeholder "Nombre"
                , value config.newUserName
                , onInput config.onName
                ]
                []
            , button [ class "primary", type_ "submit" ] [ text "Agregar" ]
            ]
        , p [ class "error" ] [ text config.error ]
        , if List.isEmpty config.users then
            p [ class "empty empty--compact" ] [ text "No hay personas activas." ]

          else
            ul [ class "user-list" ] (List.map (userRow config) config.users)
        ]


userRow : Config msg -> WorkspaceUser -> Html msg
userRow config user =
    li [ class "user-list__item" ]
        [ div [] [ text user.name ]
        , button
            [ type_ "button"
            , class "danger-button"
            , onClick (config.onDelete user.id)
            ]
            [ text "Eliminar" ]
        ]
