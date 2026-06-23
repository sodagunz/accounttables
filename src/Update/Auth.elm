module Update.Auth exposing (Config, handleState)

import Auth exposing (AuthState(..))
import Ledger exposing (LoadState(..))
import Model exposing (MigrationState(..), Model, StorageMode(..))


type alias Config msg =
    { prepareLocalMigration : Cmd msg
    , loadLedgerData : String -> Cmd msg
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
              }
            , config.loadLedgerData invitedLedgerId
            )

        Nothing ->
            if localDataExists model then
                ( { model
                    | authState = authState
                    , storageMode = CloudSynced
                    , ledgerLoadState = Loading
                    , inviteEmail = ""
                    , error = ""
                    , accountError = ""
                    , ledgerError = ""
                    , migrationState = PreparingMigration
                  }
                , config.prepareLocalMigration
                )

            else
                let
                    ledgerId : String
                    ledgerId =
                        case user.acceptedInviteLedgerId of
                            Just invitedLedgerId ->
                                invitedLedgerId

                            Nothing ->
                                if model.currentLedgerId == "" || model.currentLedgerId == Ledger.localLedgerId then
                                    user.uid

                                else
                                    model.currentLedgerId
                in
                ( { model
                    | authState = authState
                    , storageMode = CloudSynced
                    , ledgerLoadState = Loading
                    , currentLedgerId = ledgerId
                    , inviteEmail = ""
                    , error = ""
                    , accountError = ""
                    , ledgerError = ""
                  }
                , config.loadLedgerData ledgerId
                )


handleSignedOut : Config msg -> AuthState -> Model -> ( Model, Cmd msg )
handleSignedOut config authState model =
    let
        signedOutModel : Model
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
    in
    ( signedOutModel
    , config.loadLedgerData Ledger.localLedgerId
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
