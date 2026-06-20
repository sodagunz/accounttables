port module Main exposing (main)

import Accounting exposing (FilterWindow(..), SortField(..))
import Api.Dolar as Dolar exposing (ExchangeRateStatus(..), OfficialDollar)
import Auth exposing (AuthState(..))
import Browser
import Config
import Events exposing (Event)
import Export
import Flags
import Html exposing (Html)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Ledger exposing (LoadState(..))
import Model exposing (MigrationState(..), Model, StorageMode(..), TutorialState(..), TutorialStep(..))
import Task
import Time
import Tutorial
import Update.Accounts as Accounts
import Update.Auth as AuthUpdate
import Update.Movements as Movements
import Update.LedgerData as LedgerData
import Update.Ledgers as Ledgers
import Update.Sorting as Sorting
import Util.Date exposing (DateDisplay(..), dateToIso)
import View.App as AppView


type Msg
    = GotToday Time.Zone Time.Posix
    | UpdateDescription String
    | UpdateAmount String
    | UpdateAccount String
    | UpdateCurrency String
    | UpdateDate String
    | UpdateMovementType Accounting.MovementType
    | OpenAccountTool
    | SelectFilter FilterWindow
    | SelectDateDisplay DateDisplay
    | SelectDisplayCurrency Accounting.Currency
    | SelectSort SortField
    | ExportCsv
    | ExportXlsx
    | SignInWithGoogle
    | SignOut
    | AuthStateChanged Decode.Value
    | LedgerLoaded Decode.Value
    | GotExchangeRate (Result Http.Error OfficialDollar)
    | AddMovement
    | MovementIdGenerated Decode.Value
    | UpdateNewAccountName String
    | AddAccount
    | DeleteAccount String
    | SelectLedger String
    | UpdateLedgerName String
    | SaveLedgerName
    | UpdateInviteEmail String
    | InviteGuest
    | RemoveGuest String
    | ToggleAccountFilter String
    | DeleteMovement String
    | EditMovement String
    | CancelEdit
    | EventsLoaded Decode.Value
    | LocalMigrationPrepared Decode.Value
    | SelectMigrationLedger String
    | ConfirmLocalMigration
    | SkipLocalMigration
    | TutorialNext
    | TutorialBack
    | TutorialSkip
    | TutorialFinish
    | ReopenTutorial
    | DismissTutorialCompletion
    | TutorialActionReceived Decode.Value


port exportTable : Encode.Value -> Cmd msg


port signInWithGoogle : () -> Cmd msg


port signOutUser : () -> Cmd msg


port authStateChanged : (Decode.Value -> msg) -> Sub msg


port loadLedgerData : Encode.Value -> Cmd msg


port generateExpenseId : () -> Cmd msg


port expenseIdGenerated : (Decode.Value -> msg) -> Sub msg


port saveAccount : Encode.Value -> Cmd msg


port deleteAccount : Encode.Value -> Cmd msg


port inviteLedgerGuest : Encode.Value -> Cmd msg


port removeLedgerGuest : Encode.Value -> Cmd msg


port updateLedgerName : Encode.Value -> Cmd msg


port saveLastAccountSelection : Encode.Value -> Cmd msg


port appendEvent : Encode.Value -> Cmd msg


port focusAccountTool : () -> Cmd msg


port eventsLoaded : (Decode.Value -> msg) -> Sub msg


port ledgerLoaded : (Decode.Value -> msg) -> Sub msg


port prepareLocalMigration : () -> Cmd msg


port localMigrationPrepared : (Decode.Value -> msg) -> Sub msg


port mergeLocalLedgerToFirestore : Encode.Value -> Cmd msg


port saveTutorialState : Encode.Value -> Cmd msg


port showTutorialStep : Encode.Value -> Cmd msg


port openDisclosure : String -> Cmd msg


port focusElement : String -> Cmd msg


port hideTutorial : () -> Cmd msg


port refreshTutorial : () -> Cmd msg


port tutorialAction : (Decode.Value -> msg) -> Sub msg


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


init : Decode.Value -> ( Model, Cmd Msg )
init flags =
    let
        model =
            Flags.modelFromFlags flags

        baseCmds =
            [ Task.perform identity (Task.map2 GotToday Time.here Time.now)
            , Dolar.fetchOfficialDollar GotExchangeRate
            ]
    in
    ( model
    , case model.tutorialState of
        TutorialOpen step ->
            Cmd.batch (Tutorial.tutorialNavigateCmd tutorialConfig model step :: baseCmds)

        _ ->
            Cmd.batch baseCmds
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotToday zone posix ->
            let
                today =
                    dateToIso zone posix
            in
            ( { model
                | form = Accounting.setDate today model.form
                , today = today
                , zone = zone
              }
                |> Model.ensureSelectedAccount
            , Cmd.none
            )

        UpdateDescription description ->
            ( { model | form = Accounting.setDescription description model.form }, Cmd.none )

        UpdateAmount amount ->
            ( { model | form = Accounting.setAmount (String.trim amount) model.form }, Cmd.none )

        UpdateAccount accountId ->
            ( { model | form = Accounting.setAccount accountId model.form }
            , saveLastAccount model.currentLedgerId accountId
            )

        UpdateCurrency currency ->
            ( { model | form = Accounting.setCurrency (Accounting.currencyFromString currency) model.form }, Cmd.none )

        UpdateDate date ->
            ( { model | form = Accounting.setDate date model.form }, Cmd.none )

        UpdateMovementType movementType ->
            ( { model | form = Accounting.setMovementType movementType model.form }, Cmd.none )

        OpenAccountTool ->
            ( { model | accountError = "" }, focusAccountTool () )

        SelectFilter filterWindow ->
            ( { model | filterWindow = filterWindow }, Cmd.none )

        SelectDateDisplay dateDisplay ->
            ( { model | dateDisplay = dateDisplay }, Cmd.none )

        SelectDisplayCurrency currency ->
            ( { model | displayCurrency = currency }, Cmd.none )

        SelectSort sortField ->
            ( Sorting.select sortField model, Cmd.none )

        ExportCsv ->
            ( model, exportVisibleTable Export.Csv model )

        ExportXlsx ->
            ( model, exportVisibleTable Export.Xlsx model )

        SignInWithGoogle ->
            ( model, signInWithGoogle () )

        SignOut ->
            ( model, signOutUser () )

        AuthStateChanged value ->
            AuthUpdate.handleState authUpdateConfig (Auth.decodeAuthState value) model

        LedgerLoaded value ->
            LedgerData.handleLedgerLoaded ledgerDataConfig value model

        GotExchangeRate result ->
            case result of
                Ok officialDollar ->
                    ( { model
                        | exchangeRate = officialDollar.sale
                        , exchangeRateStatus = LoadedRate officialDollar.updatedAt
                      }
                    , Cmd.none
                    )

                Err _ ->
                    ( { model | exchangeRateStatus = FailedRate }, Cmd.none )

        AddMovement ->
            Movements.requestId movementsConfig model

        MovementIdGenerated value ->
            Movements.handleGeneratedId movementsConfig value model

        UpdateNewAccountName name ->
            ( { model | newAccountName = name }, Cmd.none )

        AddAccount ->
            let
                ( updatedModel, payload ) =
                    Accounts.add model

                ( finalModel, advanceCmd ) =
                    case updatedModel.tutorialState of
                        TutorialOpen AccountsStep ->
                            if not (List.isEmpty (Model.activeAccounts updatedModel)) then
                                let
                                    nextAccountsStep =
                                        Tutorial.stepAfterAccounts updatedModel
                                in
                                let
                                    nextModel =
                                        Tutorial.prepareStep nextAccountsStep { updatedModel | tutorialState = TutorialOpen nextAccountsStep, accountError = "" }
                                in
                                ( nextModel
                                , Tutorial.tutorialNavigateCmd tutorialConfig nextModel nextAccountsStep
                                )

                            else
                                ( updatedModel, Cmd.none )

                        _ ->
                            ( updatedModel, Cmd.none )
            in
            ( finalModel, Cmd.batch [ payloadCmd saveAccount payload, advanceCmd ] )

        DeleteAccount accountId ->
            let
                ( updatedModel, payload ) =
                    Accounts.delete accountId model
            in
            ( updatedModel, payloadCmd deleteAccount payload )

        SelectLedger ledgerId ->
            ( Ledgers.select ledgerId model
            , loadLedgerData (Ledger.encodeLedgerRequest ledgerId)
            )

        UpdateLedgerName name ->
            ( { model | ledgerName = name }, Cmd.none )

        SaveLedgerName ->
            let
                ( updatedModel, payload ) =
                    Ledgers.rename model
            in
            ( updatedModel, payloadCmd updateLedgerName payload )

        UpdateInviteEmail email ->
            ( { model | inviteEmail = email }, Cmd.none )

        InviteGuest ->
            let
                ( updatedModel, payload ) =
                    Ledgers.inviteGuest model
            in
            ( updatedModel, payloadCmd inviteLedgerGuest payload )

        RemoveGuest uid ->
            let
                ( updatedModel, payload ) =
                    Ledgers.removeGuest uid model
            in
            ( updatedModel, payloadCmd removeLedgerGuest payload )

        ToggleAccountFilter accountId ->
            let
                hidden =
                    model.hiddenAccountIds

                updatedHidden =
                    if List.member accountId hidden then
                        List.filter (\id -> id /= accountId) hidden

                    else
                        accountId :: hidden
            in
            ( { model | hiddenAccountIds = updatedHidden }, Cmd.none )

        DeleteMovement movementId ->
            Movements.delete movementsConfig movementId model

        EditMovement movementId ->
            Movements.edit movementId model

        CancelEdit ->
            Movements.cancelEdit model

        EventsLoaded value ->
            Movements.handleEventsLoaded value model

        LocalMigrationPrepared value ->
            LedgerData.handleLocalMigrationPrepared ledgerDataConfig value model

        SelectMigrationLedger ledgerId ->
            case model.migrationState of
                ChoosingMigration ledgers _ ->
                    ( { model | migrationState = ChoosingMigration ledgers ledgerId }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ConfirmLocalMigration ->
            case model.migrationState of
                ChoosingMigration _ ledgerId ->
                    ( { model | migrationState = UploadingMigration ledgerId, ledgerLoadState = Loading }
                    , mergeLocalLedgerToFirestore (Ledger.encodeLedgerRequest ledgerId)
                    )

                _ ->
                    ( model, Cmd.none )

        SkipLocalMigration ->
            case model.migrationState of
                ChoosingMigration _ ledgerId ->
                    ( { model | migrationState = NoMigration, ledgerLoadState = Loading }
                    , loadLedgerData (Ledger.encodeLedgerRequest ledgerId)
                    )

                UploadingMigration ledgerId ->
                    ( { model | migrationState = NoMigration, ledgerLoadState = Loading }
                    , loadLedgerData (Ledger.encodeLedgerRequest ledgerId)
                    )

                PreparingMigration ->
                    ( { model | migrationState = NoMigration }, Cmd.none )

                NoMigration ->
                    ( model, Cmd.none )

        TutorialNext ->
            case model.tutorialState of
                TutorialOpen step ->
                    Tutorial.advanceTutorialFrom tutorialConfig step model

                _ ->
                    ( model, Cmd.none )

        TutorialBack ->
            case model.tutorialState of
                TutorialOpen step ->
                    Tutorial.tutorialNavigateTo tutorialConfig (Tutorial.previousStep step) model

                _ ->
                    ( model, Cmd.none )

        TutorialSkip ->
            case model.tutorialState of
                TutorialOpen step ->
                    Tutorial.skipTutorialFrom tutorialConfig step model

                _ ->
                    ( model, Cmd.none )

        TutorialFinish ->
            Tutorial.handleTutorialAction tutorialConfig (Encode.object [ ( "action", Encode.string "done" ) ]) model

        ReopenTutorial ->
            let
                step =
                    Tutorial.reopenedStep model

                ( reopenedModel, navigateCmd ) =
                    Tutorial.tutorialNavigateTo tutorialConfig step { model | tutorialCompletionVisible = False, tutorialMovementId = Nothing }
            in
            ( reopenedModel
            , Cmd.batch
                [ saveTutorialState (Encode.string "")
                , navigateCmd
                ]
            )

        DismissTutorialCompletion ->
            ( { model | tutorialCompletionVisible = False }, Cmd.none )

        TutorialActionReceived value ->
            Tutorial.handleTutorialAction tutorialConfig value model


payloadCmd : (Encode.Value -> Cmd Msg) -> Maybe Encode.Value -> Cmd Msg
payloadCmd toCmd payload =
    payload
        |> Maybe.map toCmd
        |> Maybe.withDefault Cmd.none


view : Model -> Html Msg
view model =
    AppView.view (Config.view messages) model


messages : Config.Messages Msg
messages =
    { reopenTutorial = ReopenTutorial
    , dismissTutorialCompletion = DismissTutorialCompletion
    , signIn = SignInWithGoogle
    , signOut = SignOut
    , description = UpdateDescription
    , amount = UpdateAmount
    , account = UpdateAccount
    , createAccount = OpenAccountTool
    , currency = UpdateCurrency
    , date = UpdateDate
    , movementType = UpdateMovementType
    , submitMovement = AddMovement
    , cancelEdit = CancelEdit
    , selectFilter = SelectFilter
    , toggleAccountFilter = ToggleAccountFilter
    , selectDateDisplay = SelectDateDisplay
    , selectDisplayCurrency = SelectDisplayCurrency
    , selectSort = SelectSort
    , exportCsv = ExportCsv
    , exportXlsx = ExportXlsx
    , deleteMovement = DeleteMovement
    , editMovement = EditMovement
    , selectLedger = SelectLedger
    , ledgerName = UpdateLedgerName
    , saveLedgerName = SaveLedgerName
    , inviteEmail = UpdateInviteEmail
    , invite = InviteGuest
    , removeGuest = RemoveGuest
    , accountName = UpdateNewAccountName
    , addAccount = AddAccount
    , deleteAccount = DeleteAccount
    , selectMigrationLedger = SelectMigrationLedger
    , confirmLocalMigration = ConfirmLocalMigration
    , skipLocalMigration = SkipLocalMigration
    }


ports : Config.Ports Msg
ports =
    { showTutorialStep = showTutorialStep
    , openDisclosure = openDisclosure
    , focusElement = focusElement
    , hideTutorial = hideTutorial
    , saveTutorialState = saveTutorialState
    , mergeLocalLedgerToFirestore = mergeLocalLedgerToFirestore
    , prepareLocalMigration = prepareLocalMigration
    , loadLedgerData = loadLedgerData
    , generateExpenseId = generateExpenseId
    , appendEvent = appendEvent
    , saveLastAccount = saveLastAccount
    }


tutorialConfig : Tutorial.Config Msg
tutorialConfig =
    Config.tutorial ports


ledgerDataConfig : LedgerData.Config Msg
ledgerDataConfig =
    Config.ledgerData tutorialConfig ports


authUpdateConfig : AuthUpdate.Config Msg
authUpdateConfig =
    Config.authUpdate tutorialConfig ports


movementsConfig : Movements.Config Msg
movementsConfig =
    Config.movements tutorialConfig ports


exportVisibleTable : Export.Format -> Model -> Cmd Msg
exportVisibleTable format model =
    exportTable (Export.tablePayload format model.dateDisplay model.today (Model.activeAccounts model) (Model.visibleMovements model))


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ authStateChanged AuthStateChanged
        , ledgerLoaded LedgerLoaded
        , expenseIdGenerated MovementIdGenerated
        , eventsLoaded EventsLoaded
        , localMigrationPrepared LocalMigrationPrepared
        , tutorialAction TutorialActionReceived
        ]


saveLastAccount : String -> String -> Cmd Msg
saveLastAccount ledgerId accountId =
    if ledgerId == "" || accountId == "" then
        Cmd.none

    else
        saveLastAccountSelection
            (Encode.object
                [ ( "ledgerId", Encode.string ledgerId )
                , ( "accountId", Encode.string accountId )
                ]
            )
