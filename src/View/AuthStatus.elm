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
                    , span [ class "auth-user__skeleton auth-user__skeleton-button", attribute "aria-label" "Comprobando sesión" ] []
                    ]
                ]

            AuthUnconfigured ->
                [ p [] [ text "Firebase no configurado." ] ]

            SignedOut ->
                [ button [ type_ "button", class "auth-button auth-button--google auth-button--icon-only", attribute "data-tutorial" "sign-in", attribute "aria-label" "Ingresar con Google", title "Ingresar con Google", onClick config.onSignIn ]
                    [ googleIcon ]
                ]

            SignedIn _ ->
                [ div [ class "auth-user" ]
                    [ syncDot config.ledgerLoadState
                    , button [ type_ "button", class "auth-button auth-button--icon-only", attribute "aria-label" "Cerrar sesión", onClick config.onSignOut ] [ signOutIcon ]
                    ]
                , ledgerStatus config.ledgerLoadState
                ]

            AuthError message ->
                [ p [ class "auth-error" ] [ text message ]
                , button [ type_ "button", class "auth-button", onClick config.onSignIn ] [ text "Reintentar" ]
                ]
        )


googleIcon : Html msg
googleIcon =
    span
        [ class "auth-button__icon auth-button__icon--google"
        , attribute "aria-hidden" "true"
        ]
        []


signOutIcon : Html msg
signOutIcon =
    span
        [ class "auth-button__icon auth-button__icon--sign-out"
        , attribute "aria-hidden" "true"
        ]
        []


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
