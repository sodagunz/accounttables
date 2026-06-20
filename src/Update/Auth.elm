module Update.Auth exposing (Config, handleState, localDataExists)

import Auth exposing (AuthState(..))
import Ledger exposing (LoadState(..))
import Model exposing (MigrationState(..), Model, StorageMode(..), TutorialState(..), TutorialStep(..))
import Tutorial


type alias Config msg =
    { prepareLocalMigration : Cmd msg
    , loadLedgerData : String -> Cmd msg
    , completeTutorial : Cmd msg
    , tutorialAdvanceCmd : Model -> TutorialState -> TutorialState -> Cmd msg
    , tutorialNavigateCmd : Model -> TutorialStep -> Cmd msg
    }


handleState : Config msg -> AuthState -> Model -> ( Model, Cmd msg )
handleState config authState model =
    case authState of
        SignedIn user ->
            handleSignedIn config authState user model

        SignedOut ->
            handleSignedOut config authState model

        AuthUnconfigured ->
            handleAuthUnconfigured config authState model

        _ ->
            ( { model | authState = authState }, Cmd.none )


handleSignedIn : Config msg -> AuthState -> Auth.User -> Model -> ( Model, Cmd msg )
handleSignedIn config authState user model =
    let
        ledgerId =
            case user.acceptedInviteLedgerId of
                Just invitedLedgerId ->
                    invitedLedgerId

                Nothing ->
                    if model.currentLedgerId == "" || model.currentLedgerId == Ledger.localLedgerId then
                        user.uid

                    else
                        model.currentLedgerId

        newTutorialState =
            tutorialAfterAuth model
    in
    case user.acceptedInviteLedgerId of
        Just invitedLedgerId ->
            ( { model
                | authState = authState
                , storageMode = CloudSynced
                , ledgerLoadState = Loading
                , currentLedgerId = invitedLedgerId
                , inviteEmail = ""
                , error = ""
                , accountError = ""
                , ledgerError = ""
                , migrationState = NoMigration
                , tutorialState = TutorialCompleted
                , tutorialCompletionVisible = False
                , tutorialMovementId = Nothing
              }
            , Cmd.batch
                [ config.completeTutorial
                , config.loadLedgerData invitedLedgerId
                ]
            )

        Nothing ->
            if localDataExists model then
                let
                    updatedModel =
                        { model
                            | authState = authState
                            , storageMode = CloudSynced
                            , ledgerLoadState = Loading
                            , inviteEmail = ""
                            , error = ""
                            , accountError = ""
                            , ledgerError = ""
                            , migrationState = PreparingMigration
                            , tutorialState = newTutorialState
                        }
                            |> Tutorial.prepareState
                in
                ( updatedModel
                , Cmd.batch
                    [ config.prepareLocalMigration
                    , config.tutorialAdvanceCmd updatedModel model.tutorialState updatedModel.tutorialState
                    ]
                )

            else
                let
                    updatedModel =
                        { model
                            | authState = authState
                            , storageMode = CloudSynced
                            , ledgerLoadState = Loading
                            , currentLedgerId = ledgerId
                            , inviteEmail = ""
                            , error = ""
                            , accountError = ""
                            , ledgerError = ""
                            , tutorialState = newTutorialState
                        }
                            |> Tutorial.prepareState
                in
                ( updatedModel
                , Cmd.batch
                    [ config.loadLedgerData ledgerId
                    , config.tutorialAdvanceCmd updatedModel model.tutorialState updatedModel.tutorialState
                    ]
                )


handleSignedOut : Config msg -> AuthState -> Model -> ( Model, Cmd msg )
handleSignedOut config authState model =
    let
        signedOutModel =
            { model
                | authState = authState
                , inviteEmail = ""
                , error = ""
                , accountError = ""
                , ledgerError = ""
            }
                |> Ledger.ensureLocalLedger LocalOnly
                |> Model.ensureSelectedAccount

        tutorialCmd =
            case signedOutModel.tutorialState of
                TutorialOpen SignInStep ->
                    config.tutorialNavigateCmd signedOutModel SignInStep

                _ ->
                    Cmd.none
    in
    ( signedOutModel
    , Cmd.batch
        [ config.loadLedgerData Ledger.localLedgerId
        , tutorialCmd
        ]
    )


handleAuthUnconfigured : Config msg -> AuthState -> Model -> ( Model, Cmd msg )
handleAuthUnconfigured config authState model =
    ( { model
        | authState = authState
        , inviteEmail = ""
        , error = ""
        , accountError = ""
        , ledgerError = ""
      }
        |> Ledger.ensureLocalLedger LocalOnly
        |> Model.ensureSelectedAccount
    , config.loadLedgerData Ledger.localLedgerId
    )


localDataExists : Model -> Bool
localDataExists model =
    model.storageMode
        == LocalOnly
        && (not (List.isEmpty model.events)
                || not (List.isEmpty model.accounts)
                || model.ledgerName
                /= Ledger.localLedgerName
           )


tutorialAfterAuth : Model -> TutorialState
tutorialAfterAuth model =
    case model.tutorialState of
        TutorialOpen SignInStep ->
            TutorialOpen (Tutorial.reopenedStep model)

        _ ->
            model.tutorialState
