module View.WorkspaceAccess exposing (Config, view)

import Auth
import Html exposing (Html, button, div, input, label, li, option, p, section, select, span, text, ul)
import Html.Attributes exposing (class, placeholder, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Workspace exposing (Member, WorkspaceSummary)


type alias Config msg =
    { authState : Auth.AuthState
    , workspaces : List WorkspaceSummary
    , currentWorkspaceId : String
    , workspaceName : String
    , inviteEmail : String
    , error : String
    , onSelectWorkspace : String -> msg
    , onWorkspaceName : String -> msg
    , onSaveWorkspaceName : msg
    , onInviteEmail : String -> msg
    , onInvite : msg
    , onRemoveGuest : String -> msg
    }


view : Config msg -> Html msg
view config =
    section [ class "panel workspace-panel" ]
        [ Html.h2 [ class "section-title" ] [ text "Workspace" ]
        , workspaceSelect config
        , workspaceNameForm config
        , memberList config
        , inviteForm config
        , p [ class "error" ] [ text config.error ]
        ]


workspaceSelect : Config msg -> Html msg
workspaceSelect config =
    label []
        [ text "Activo"
        , select [ value config.currentWorkspaceId, onInput config.onSelectWorkspace ]
            (List.map workspaceOption config.workspaces)
        ]


workspaceOption : WorkspaceSummary -> Html msg
workspaceOption workspace =
    option [ value workspace.id ] [ text workspace.name ]


workspaceNameForm : Config msg -> Html msg
workspaceNameForm config =
    case currentWorkspace config of
        Just workspace ->
            if isOwner config workspace then
                Html.form [ class "user-form", onSubmit config.onSaveWorkspaceName ]
                    [ input
                        [ type_ "text"
                        , placeholder "Nombre del workspace"
                        , value config.workspaceName
                        , onInput config.onWorkspaceName
                        ]
                        []
                    , button [ class "primary", type_ "submit" ] [ text "Guardar" ]
                    ]

            else
                text ""

        Nothing ->
            text ""


memberList : Config msg -> Html msg
memberList config =
    case currentWorkspace config of
        Nothing ->
            p [ class "empty empty--compact" ] [ text "No hay workspace activo." ]

        Just workspace ->
            ul [ class "member-list" ] (List.map (memberRow config workspace) workspace.members)


memberRow : Config msg -> WorkspaceSummary -> Member -> Html msg
memberRow config workspace member =
    li [ class "member-list__item" ]
        [ div []
            [ span [] [ text (memberLabel member) ]
            , if member.uid == workspace.ownerUid then
                span [ class "member-role" ] [ text "Owner" ]

              else
                text ""
            ]
        , if canRemoveMember config workspace member then
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
    case currentWorkspace config of
        Just workspace ->
            if isOwner config workspace then
                Html.form [ class "user-form", onSubmit config.onInvite ]
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


canRemoveMember : Config msg -> WorkspaceSummary -> Member -> Bool
canRemoveMember config workspace member =
    isOwner config workspace && member.uid /= workspace.ownerUid


isOwner : Config msg -> WorkspaceSummary -> Bool
isOwner config workspace =
    case config.authState of
        Auth.SignedIn user ->
            user.uid == workspace.ownerUid

        _ ->
            False


currentWorkspace : Config msg -> Maybe WorkspaceSummary
currentWorkspace config =
    config.workspaces
        |> List.filter (\workspace -> workspace.id == config.currentWorkspaceId)
        |> List.head
