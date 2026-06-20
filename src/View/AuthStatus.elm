module View.AuthStatus exposing (Config, view)

import Auth exposing (AuthState(..))
import Html exposing (Html, button, div, p, span, text)
import Html.Attributes exposing (attribute, class, title, type_)
import Html.Events exposing (onClick)
import Ledger exposing (LoadState(..))


type alias Config msg =
    { authState : AuthState
    , ledgerLoadState : LoadState
    , onSignIn : msg
    , onSignOut : msg
    }


view : Config msg -> Html msg
view config =
    div [ class "auth-status" ]
        (case config.authState of
            AuthLoading ->
                [ div [ class "auth-user" ]
                    [ syncDot Loading
                    , span [ class "auth-user__skeleton auth-user__skeleton-name", attribute "aria-label" "Comprobando sesión" ] []
                    , span [ class "auth-user__skeleton auth-user__skeleton-button", attribute "aria-hidden" "true" ] []
                    ]
                ]

            AuthUnconfigured ->
                [ p [] [ text "Firebase no configurado." ] ]

            SignedOut ->
                [ button [ type_ "button", class "auth-button", attribute "data-tutorial" "sign-in", onClick config.onSignIn ] [ text "Ingresar con Google" ] ]

            SignedIn user ->
                [ div [ class "auth-user" ]
                    [ syncDot config.ledgerLoadState
                    , span [ class "auth-user__name" ] [ text (userLabel user) ]
                    , button [ type_ "button", class "auth-button", attribute "aria-label" "Cerrar sesión", onClick config.onSignOut ] [ text "⏻" ]
                    ]
                , ledgerStatus config.ledgerLoadState
                ]

            AuthError message ->
                [ p [ class "auth-error" ] [ text message ]
                , button [ type_ "button", class "auth-button", onClick config.onSignIn ] [ text "Reintentar" ]
                ]
        )


ledgerStatus : LoadState -> Html msg
ledgerStatus loadState =
    case loadState of
        NotLoaded ->
            text ""

        Loading ->
            text ""

        Loaded ->
            text ""

        LoadError message ->
            p [ class "auth-error" ] [ text message ]


syncDot : LoadState -> Html msg
syncDot loadState =
    let
        status : ( String, String )
        status =
            case loadState of
                NotLoaded ->
                    ( "sync-dot--syncing", "Sincronizando" )

                Loading ->
                    ( "sync-dot--syncing", "Sincronizando" )

                Loaded ->
                    ( "sync-dot--synced", "Sincronizado" )

                LoadError _ ->
                    ( "sync-dot--error", "Error de sincronización" )

        statusClass : String
        statusClass =
            Tuple.first status

        statusLabel : String
        statusLabel =
            Tuple.second status
    in
    span
        [ class ("sync-dot " ++ statusClass)
        , title statusLabel
        , attribute "aria-label" statusLabel
        ]
        []


userLabel : Auth.User -> String
userLabel user =
    if user.displayName /= "" then
        user.displayName

    else if user.email /= "" then
        user.email

    else
        "Sesión iniciada"
