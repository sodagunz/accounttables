module Update.LedgerData exposing
    ( Config
    , apply
    , handleLedgerLoaded
    , handleLocalMigrationPrepared
    )

import Accounting
import Json.Decode as Decode
import Ledger exposing (LoadState(..))
import Model exposing (MigrationState(..), Model, StorageMode(..))
import Projector


type alias Config msg =
    { mergeLocalLedgerToFirestore : String -> Cmd msg
    }


handleLedgerLoaded : Decode.Value -> Model -> ( Model, Cmd msg )
handleLedgerLoaded value model =
    case Ledger.decodeLedger value of
        Ok ledger ->
            ( apply ledger model, Cmd.none )

        Err error ->
            ( { model | ledgerLoadState = LoadError error, migrationState = NoMigration }, Cmd.none )


handleLocalMigrationPrepared : Config msg -> Decode.Value -> Model -> ( Model, Cmd msg )
handleLocalMigrationPrepared config value model =
    let
        status : String
        status =
            Decode.decodeValue (Decode.field "status" Decode.string) value
                |> Result.withDefault "error"
    in
    if status == "ready" then
        case Ledger.decodeLedgerSummaries value of
            Ok ledgers ->
                case ledgers of
                    [] ->
                        ( { model
                            | migrationState = NoMigration
                            , ledgerLoadState = LoadError "No se encontró un libro de Firestore para subir los datos locales."
                          }
                        , Cmd.none
                        )

                    [ ledger ] ->
                        ( { model
                            | migrationState = UploadingMigration ledger.id
                            , ledgerLoadState = Loading
                          }
                        , config.mergeLocalLedgerToFirestore ledger.id
                        )

                    firstLedger :: _ ->
                        let
                            selectedLedgerId : String
                            selectedLedgerId =
                                Decode.decodeValue (Decode.field "selectedLedgerId" Decode.string) value
                                    |> Result.withDefault firstLedger.id
                        in
                        ( { model
                            | migrationState = ChoosingMigration ledgers selectedLedgerId
                            , ledgerLoadState = Loaded
                          }
                        , Cmd.none
                        )

            Err error ->
                ( { model | migrationState = NoMigration, ledgerLoadState = LoadError error }, Cmd.none )

    else
        let
            error : String
            error =
                Decode.decodeValue (Decode.field "message" Decode.string) value
                    |> Result.withDefault "No se pudo preparar la migración local."
        in
        ( { model | migrationState = NoMigration, ledgerLoadState = LoadError error }, Cmd.none )


apply : Ledger.LedgerData -> Model -> Model
apply ledger model =
    let
        accounts : List Accounting.Account
        accounts =
            Model.activeAccountsFromList ledger.accounts

        form : Accounting.Form
        form =
            formWithLoadedAccount ledger.lastAccountId accounts model.form

        expenses : List Accounting.Movement
        expenses =
            if List.isEmpty ledger.events then
                Model.activeMovements ledger.expenses

            else
                Model.activeMovements (Projector.projectEvents ledger.events)
    in
    { model
        | events = ledger.events
        , expenses = expenses
        , accounts = accounts
        , ledgers = ledger.ledgers
        , currentLedgerId = ledger.currentLedgerId
        , ledgerName = Model.ledgerNameFor ledger.currentLedgerId ledger.ledgers
        , storageMode =
            if ledger.currentLedgerId == Ledger.localLedgerId then
                LocalOnly

            else
                CloudSynced
        , form = form
        , ledgerLoadState = Loaded
        , error = ""
        , accountError = ""
        , ledgerError = ""
        , migrationState = NoMigration
    }
        |> Model.ensureSelectedAccount


formWithLoadedAccount : Maybe String -> List Accounting.Account -> Accounting.Form -> Accounting.Form
formWithLoadedAccount lastAccountId accounts form =
    case lastAccountId of
        Just accountId ->
            if List.any (\account -> account.id == accountId) accounts then
                Accounting.setAccount accountId form

            else
                Accounting.setAccount "" form

        Nothing ->
            if List.any (\account -> account.id == form.accountId) accounts then
                form

            else
                Accounting.setAccount "" form
