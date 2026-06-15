module View.LedgerAccess exposing (Config, view)

import Auth
import Html exposing (Html, button, div, input, label, li, option, p, section, select, span, strong, text, ul)
import Html.Attributes exposing (class, placeholder, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Ledger exposing (LedgerSummary, Member)


type alias Config msg =
    { authState : Auth.AuthState
    , ledgers : List LedgerSummary
    , currentLedgerId : String
    , ledgerName : String
    , inviteEmail : String
    , error : String
    , onSelectLedger : String -> msg
    , onLedgerName : String -> msg
    , onSaveLedgerName : msg
    , onInviteEmail : String -> msg
    , onInvite : msg
    , onRemoveGuest : String -> msg
    }


view : Config msg -> Html msg
view config =
    section [ class "admin-section ledger-panel" ]
        [ div [ class "ledger-context" ]
            [ div []
                [ Html.h2 [ class "section-title ledger-context__title" ] [ text "Libro contable" ]
                , p [ class "ledger-context__name" ] [ text (currentLedgerName config) ]
                ]
            ]
        , ledgerControls config
        , memberControls config
        , p [ class "error" ] [ text config.error ]
        ]


ledgerControls : Config msg -> Html msg
ledgerControls config =
    Html.details [ class "ledger-disclosure" ]
        [ Html.summary [ class "ledger-disclosure__summary" ]
            [ span [] [ text "Cambiar o renombrar" ]
            , strong [] [ text "Libro contable" ]
            ]
        , div [ class "ledger-disclosure__content" ]
            [ ledgerSelect config
            , ledgerNameForm config
            ]
        ]


ledgerSelect : Config msg -> Html msg
ledgerSelect config =
    label []
        [ text "Activo"
        , select [ value config.currentLedgerId, onInput config.onSelectLedger ]
            (List.map ledgerOption config.ledgers)
        ]


ledgerOption : LedgerSummary -> Html msg
ledgerOption ledger =
    option [ value ledger.id ] [ text ledger.name ]


ledgerNameForm : Config msg -> Html msg
ledgerNameForm config =
    case currentLedger config of
        Just ledger ->
            if isOwner config ledger then
                Html.form [ class "inline-form", onSubmit config.onSaveLedgerName ]
                    [ input
                        [ type_ "text"
                        , placeholder "Nombre del libro contable"
                        , value config.ledgerName
                        , onInput config.onLedgerName
                        ]
                        []
                    , button [ class "primary", type_ "submit" ] [ text "Guardar" ]
                    ]

            else
                text ""

        Nothing ->
            text ""


memberControls : Config msg -> Html msg
memberControls config =
    Html.details [ class "members-disclosure" ]
        [ Html.summary [ class "members-disclosure__summary" ]
            [ span [] [ text "Invitaciones y acceso" ]
            , strong [] [ text "Miembros" ]
            ]
        , div [ class "members-disclosure__content" ]
            (case config.authState of
                Auth.SignedIn _ ->
                    [ memberList config
                    , inviteForm config
                    ]

                _ ->
                    [ p [ class "empty empty--compact" ] [ text "Ingresa con Google para invitar colaboradores y sincronizar este libro." ] ]
            )
        ]


memberList : Config msg -> Html msg
memberList config =
    case currentLedger config of
        Nothing ->
            p [ class "empty empty--compact" ] [ text "No hay libro contable activo." ]

        Just ledger ->
            ul [ class "member-list" ] (List.map (memberRow config ledger) ledger.members)


memberRow : Config msg -> LedgerSummary -> Member -> Html msg
memberRow config ledger member =
    li [ class "member-list__item" ]
        [ div []
            [ span [] [ text (memberLabel member) ]
            , if member.uid == ledger.ownerUid then
                span [ class "member-role" ] [ text "Owner" ]

              else
                text ""
            ]
        , if canRemoveMember config ledger member then
            button
                [ type_ "button"
                , class "danger-button"
                , onClick (config.onRemoveGuest member.uid)
                ]
                [ text "Quitar" ]

          else
            text ""
        ]


memberLabel : Member -> String
memberLabel member =
    if member.displayName /= "" then
        member.displayName ++ " <" ++ member.email ++ ">"

    else
        member.email


inviteForm : Config msg -> Html msg
inviteForm config =
    case currentLedger config of
        Just ledger ->
            if isOwner config ledger then
                Html.form [ class "inline-form", onSubmit config.onInvite ]
                    [ input
                        [ type_ "email"
                        , placeholder "Invitar por email"
                        , value config.inviteEmail
                        , onInput config.onInviteEmail
                        ]
                        []
                    , button [ class "primary", type_ "submit" ] [ text "Invitar" ]
                    ]

            else
                text ""

        Nothing ->
            text ""


canRemoveMember : Config msg -> LedgerSummary -> Member -> Bool
canRemoveMember config ledger member =
    isOwner config ledger && member.uid /= ledger.ownerUid


isOwner : Config msg -> LedgerSummary -> Bool
isOwner config ledger =
    case config.authState of
        Auth.SignedIn user ->
            user.uid == ledger.ownerUid

        _ ->
            False


currentLedger : Config msg -> Maybe LedgerSummary
currentLedger config =
    config.ledgers
        |> List.filter (\ledger -> ledger.id == config.currentLedgerId)
        |> List.head


currentLedgerName : Config msg -> String
currentLedgerName config =
    currentLedger config
        |> Maybe.map .name
        |> Maybe.withDefault "Sin libro contable activo"
