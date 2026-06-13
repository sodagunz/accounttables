module View.AuthStatus exposing (Config, view)

import Auth exposing (AuthState(..))
import Html exposing (Html, button, div, p, span, text)
import Html.Attributes exposing (class, type_)
import Html.Events exposing (onClick)
import Workspace exposing (LoadState(..))


type alias Config msg =
    { authState : AuthState
    , workspaceLoadState : LoadState
    , onSignIn : msg
    , onSignOut : msg
    }


view : Config msg -> Html msg
view config =
    div [ class "auth-status" ]
        (case config.authState of
            AuthLoading ->
                [ p [] [ text "Comprobando sesión..." ] ]

            AuthUnconfigured ->
                [ p [] [ text "Firebase no configurado." ] ]

            SignedOut ->
                [ button [ type_ "button", class "auth-button", onClick config.onSignIn ] [ text "Ingresar con Google" ] ]

            SignedIn user ->
                [ div [ class "auth-user" ]
                    [ span [] [ text (userLabel user) ]
                    , button [ type_ "button", class "auth-button", onClick config.onSignOut ] [ text "Salir" ]
                    ]
                , workspaceStatus config.workspaceLoadState
                ]

            AuthError message ->
                [ p [ class "auth-error" ] [ text message ]
                , button [ type_ "button", class "auth-button", onClick config.onSignIn ] [ text "Reintentar" ]
                ]
        )


workspaceStatus : LoadState -> Html msg
workspaceStatus loadState =
    case loadState of
        NotLoaded ->
            p [ class "auth-meta" ] [ text "Datos locales" ]

        Loading ->
            p [ class "auth-meta" ] [ text "Cargando datos..." ]

        Loaded ->
            p [ class "auth-meta" ] [ text "Datos sincronizados" ]

        LoadError message ->
            p [ class "auth-error" ] [ text message ]


userLabel : Auth.User -> String
userLabel user =
    if user.displayName /= "" then
        user.displayName

    else if user.email /= "" then
        user.email

    else
        "Sesión iniciada"
