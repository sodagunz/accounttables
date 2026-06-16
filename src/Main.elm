port module Main exposing (main)

import Accounting exposing (FilterWindow(..), SortDirection(..), SortField(..))
import Api.Dolar as Dolar exposing (ExchangeRateStatus(..), OfficialDollar)
import Auth exposing (AuthState(..))
import Browser
import Events exposing (Event)
import Export
import Html exposing (Html)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Ledger exposing (LoadState(..))
import Model exposing (MigrationState(..), Model, StorageMode(..), TutorialState(..), TutorialStep(..))
import Projector
import Task
import Time
import Tutorial
import Update.Accounts as Accounts
import Update.Ledgers as Ledgers
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
    | AddExpense
    | ExpenseIdGenerated Decode.Value
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
    | DeleteExpense String
    | EditExpense String
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
            modelFromFlags flags

        baseCmds =
            [ Task.perform identity (Task.map2 GotToday Time.here Time.now)
            , Dolar.fetchOfficialDollar GotExchangeRate
            ]
    in
    ( model
    , case model.tutorialState of
        TutorialOpen step ->
            Cmd.batch (tutorialNavigateCmd model step :: baseCmds)

        _ ->
            Cmd.batch baseCmds
    )


modelFromFlags : Decode.Value -> Model
modelFromFlags flags =
    let
        tutorialState =
            decodeTutorialStateFromFlags flags

        initialModel =
            Model.initial

        baseModel =
            { initialModel | tutorialState = tutorialState }

        ledgerResult =
            case Decode.decodeValue (Decode.field "ledger" Decode.value) flags of
                Ok ledgerValue ->
                    Ledger.decodeLedger ledgerValue

                Err _ ->
                    Ledger.decodeLedger flags
    in
    case ledgerResult of
        Ok ledger ->
            applyLedgerData ledger baseModel

        Err _ ->
            baseModel


decodeTutorialStateFromFlags : Decode.Value -> TutorialState
decodeTutorialStateFromFlags flags =
    case Decode.decodeValue (Decode.field "tutorialState" Decode.string) flags of
        Ok "dismissed" ->
            TutorialDismissed

        Ok "completed" ->
            TutorialCompleted

        _ ->
            TutorialOpen SignInStep


localLedgerId : String
localLedgerId =
    "local"


localLedgerName : String
localLedgerName =
    "Libro contable de desconocido"


ensureLocalLedger : Model -> Model
ensureLocalLedger model =
    if model.currentLedgerId == localLedgerId then
        { model
            | storageMode = LocalOnly
            , ledgerLoadState = Loaded
        }

    else
        { model
            | storageMode = LocalOnly
            , ledgerLoadState = Loaded
            , currentLedgerId = localLedgerId
            , ledgerName = localLedgerName
            , ledgers =
                [ { id = localLedgerId
                  , name = localLedgerName
                  , ownerUid = ""
                  , members = []
                  , invitedEmails = []
                  }
                ]
        }


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
            ( selectSort sortField model, Cmd.none )

        ExportCsv ->
            ( model, exportVisibleTable Export.Csv model )

        ExportXlsx ->
            ( model, exportVisibleTable Export.Xlsx model )

        SignInWithGoogle ->
            ( model, signInWithGoogle () )

        SignOut ->
            ( model, signOutUser () )

        AuthStateChanged value ->
            handleAuthStateChanged (Auth.decodeAuthState value) model

        LedgerLoaded value ->
            handleLedgerLoaded value model

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

        AddExpense ->
            ( model, generateExpenseId () )

        ExpenseIdGenerated value ->
            case Decode.decodeValue Decode.string value of
                Ok expenseId ->
                    let
                        readyModel =
                            Model.ensureSelectedAccount model

                        rate =
                            case readyModel.form.editingId of
                                Just editingId ->
                                    case List.head (List.filter (\e -> e.id == editingId) readyModel.expenses) of
                                        Just expense ->
                                            expense.exchangeRate

                                        Nothing ->
                                            readyModel.exchangeRate

                                Nothing ->
                                    readyModel.exchangeRate
                    in
                    case Accounting.buildExpense rate expenseId (Model.activeAccounts readyModel) readyModel.form of
                        Ok expense ->
                            let
                                ( event, updatedModel ) =
                                    case readyModel.form.editingId of
                                        Just editingId ->
                                            let
                                                updateEvent =
                                                    Events.MovementUpdatedEvent 0
                                                        { movementId = editingId
                                                        , movementType = expense.movementType
                                                        , description = expense.description
                                                        , accountId = expense.accountId
                                                        , accountName = expense.accountName
                                                        , inputAmount = expense.inputAmount
                                                        , inputCurrency = expense.inputCurrency
                                                        , exchangeRate = expense.exchangeRate
                                                        , ars = expense.ars
                                                        , usd = expense.usd
                                                        , date = expense.date
                                                        }

                                                updatedExpenses =
                                                    List.map
                                                        (\e ->
                                                            if e.id == editingId then
                                                                expense

                                                            else
                                                                e
                                                        )
                                                        readyModel.expenses
                                            in
                                            ( updateEvent
                                            , { readyModel
                                                | events = updateEvent :: readyModel.events
                                                , expenses = Model.activeExpenses updatedExpenses
                                              }
                                            )

                                        Nothing ->
                                            let
                                                createEvent =
                                                    Events.MovementCreatedEvent 0
                                                        { id = expense.id
                                                        , movementType = expense.movementType
                                                        , description = expense.description
                                                        , accountId = expense.accountId
                                                        , accountName = expense.accountName
                                                        , inputAmount = expense.inputAmount
                                                        , inputCurrency = expense.inputCurrency
                                                        , exchangeRate = expense.exchangeRate
                                                        , ars = expense.ars
                                                        , usd = expense.usd
                                                        , date = expense.date
                                                        }
                                            in
                                            ( createEvent
                                            , { readyModel
                                                | events = createEvent :: readyModel.events
                                                , expenses = expense :: Model.activeExpenses readyModel.expenses
                                              }
                                            )
                            in
                            let
                                isNewExpense =
                                    case readyModel.form.editingId of
                                        Nothing ->
                                            True

                                        Just _ ->
                                            False

                                ( modelAfterAdvance, advanceCmd ) =
                                    if isNewExpense then
                                        case updatedModel.tutorialState of
                                            TutorialOpen FirstExpenseStep ->
                                                tutorialNavigateTo DeleteExpenseStep { updatedModel | tutorialExpenseId = Just expense.id }

                                            _ ->
                                                ( updatedModel, Cmd.none )

                                    else
                                        ( updatedModel, Cmd.none )
                            in
                            ( { modelAfterAdvance
                                | form =
                                    { description = ""
                                    , amount = ""
                                    , accountId = readyModel.form.accountId
                                    , currency = readyModel.form.currency
                                    , date = readyModel.form.date
                                    , movementType = readyModel.form.movementType
                                    , editingId = Nothing
                                    }
                                , error = ""
                              }
                            , Cmd.batch
                                [ appendEvent
                                    (Encode.object
                                        [ ( "ledgerId", Encode.string readyModel.currentLedgerId )
                                        , ( "event", Events.eventEncoder event )
                                        ]
                                    )
                                , saveLastAccount readyModel.currentLedgerId readyModel.form.accountId
                                , advanceCmd
                                ]
                            )

                        Err error ->
                            ( { readyModel | error = error }, Cmd.none )

                Err error ->
                    ( { model | error = Decode.errorToString error }, Cmd.none )

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
                                , tutorialNavigateCmd nextModel nextAccountsStep
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

        DeleteExpense movementId ->
            let
                isTutorialDelete =
                    case ( model.tutorialState, model.tutorialExpenseId ) of
                        ( TutorialOpen DeleteExpenseStep, Just tutorialExpenseId ) ->
                            tutorialExpenseId == movementId

                        _ ->
                            False

                event =
                    Events.MovementDeletedEvent 0 { movementId = movementId }

                updatedExpenses =
                    List.map
                        (\e ->
                            if e.id == movementId then
                                { e | deletedAt = Just "deleted" }

                            else
                                e
                        )
                        model.expenses

                baseModel =
                    { model
                        | events = event :: model.events
                        , expenses = Model.activeExpenses updatedExpenses
                    }
            in
            ( if isTutorialDelete then
                { baseModel | tutorialState = TutorialCompleted, tutorialCompletionVisible = True, tutorialExpenseId = Nothing }

              else
                baseModel
            , Cmd.batch
                [ if isTutorialDelete then
                    hideTutorial ()

                  else
                    Cmd.none
                , appendEvent
                    (Encode.object
                        [ ( "ledgerId", Encode.string model.currentLedgerId )
                        , ( "event", Events.eventEncoder event )
                        ]
                    )
                , if isTutorialDelete then
                    saveTutorialState (Encode.string "completed")

                  else
                    Cmd.none
                ]
            )

        EditExpense expenseId ->
            case List.head (List.filter (\e -> e.id == expenseId) model.expenses) of
                Just expense ->
                    ( { model
                        | form = Accounting.expenseToForm expense model.form
                        , error = ""
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( { model | error = "No se encontró el gasto a editar" }, Cmd.none )

        CancelEdit ->
            ( { model
                | form = Accounting.emptyForm
                , error = ""
              }
                |> Model.ensureSelectedAccount
            , Cmd.none
            )

        EventsLoaded value ->
            case Decode.decodeValue (Decode.list Events.eventDecoder) value of
                Ok events ->
                    let
                        projectedExpenses =
                            Projector.projectEvents events
                    in
                    ( { model
                        | events = events
                        , expenses = Model.activeExpenses projectedExpenses
                      }
                    , Cmd.none
                    )

                Err error ->
                    ( { model | error = Decode.errorToString error }, Cmd.none )

        LocalMigrationPrepared value ->
            handleLocalMigrationPrepared value model

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
                    advanceTutorialFrom step model

                _ ->
                    ( model, Cmd.none )

        TutorialBack ->
            case model.tutorialState of
                TutorialOpen step ->
                    tutorialNavigateTo (Tutorial.previousStep step) model

                _ ->
                    ( model, Cmd.none )

        TutorialSkip ->
            case model.tutorialState of
                TutorialOpen step ->
                    skipTutorialFrom step model

                _ ->
                    ( model, Cmd.none )

        TutorialFinish ->
            ( { model | tutorialState = TutorialCompleted, tutorialCompletionVisible = True, tutorialExpenseId = Nothing }
            , Cmd.batch
                [ hideTutorial ()
                , saveTutorialState (Encode.string "completed")
                ]
            )

        ReopenTutorial ->
            let
                step =
                    Tutorial.reopenedStep model

                ( reopenedModel, navigateCmd ) =
                    tutorialNavigateTo step { model | tutorialCompletionVisible = False, tutorialExpenseId = Nothing }
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
            handleTutorialAction value model


payloadCmd : (Encode.Value -> Cmd Msg) -> Maybe Encode.Value -> Cmd Msg
payloadCmd toCmd payload =
    payload
        |> Maybe.map toCmd
        |> Maybe.withDefault Cmd.none


view : Model -> Html Msg
view model =
    AppView.view viewConfig model


viewConfig : AppView.Config Msg
viewConfig =
    { localLedgerName = localLedgerName
    , onReopenTutorial = ReopenTutorial
    , onDismissTutorialCompletion = DismissTutorialCompletion
    , onSignIn = SignInWithGoogle
    , onSignOut = SignOut
    , onDescription = UpdateDescription
    , onAmount = UpdateAmount
    , onAccount = UpdateAccount
    , onCreateAccount = OpenAccountTool
    , onCurrency = UpdateCurrency
    , onDate = UpdateDate
    , onMovementType = UpdateMovementType
    , onSubmitExpense = AddExpense
    , onCancelEdit = CancelEdit
    , onSelectFilter = SelectFilter
    , onToggleAccountFilter = ToggleAccountFilter
    , onSelectDateDisplay = SelectDateDisplay
    , onSelectDisplayCurrency = SelectDisplayCurrency
    , onSelectSort = SelectSort
    , onExportCsv = ExportCsv
    , onExportXlsx = ExportXlsx
    , onDeleteExpense = DeleteExpense
    , onEditExpense = EditExpense
    , onSelectLedger = SelectLedger
    , onLedgerName = UpdateLedgerName
    , onSaveLedgerName = SaveLedgerName
    , onInviteEmail = UpdateInviteEmail
    , onInvite = InviteGuest
    , onRemoveGuest = RemoveGuest
    , onAccountName = UpdateNewAccountName
    , onAddAccount = AddAccount
    , onDeleteAccount = DeleteAccount
    , onSelectMigrationLedger = SelectMigrationLedger
    , onConfirmLocalMigration = ConfirmLocalMigration
    , onSkipLocalMigration = SkipLocalMigration
    }


handleTutorialAction : Decode.Value -> Model -> ( Model, Cmd Msg )
handleTutorialAction value model =
    case Decode.decodeValue Tutorial.actionDecoder value of
        Ok "next" ->
            update TutorialNext model

        Ok "back" ->
            update TutorialBack model

        Ok "skip" ->
            update TutorialSkip model

        Ok "done" ->
            update TutorialFinish model

        Ok "target-missing" ->
            ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


advanceTutorialFrom : TutorialStep -> Model -> ( Model, Cmd Msg )
advanceTutorialFrom step model =
    case step of
        AccountsStep ->
            let
                next =
                    Tutorial.stepAfterAccounts model
            in
            tutorialNavigateTo next model

        _ ->
            case Tutorial.nextStep step of
                Just nextStep ->
                    tutorialNavigateTo nextStep model

                Nothing ->
                    ( { model | tutorialState = TutorialCompleted, tutorialCompletionVisible = True, tutorialExpenseId = Nothing }
                    , Cmd.batch
                        [ hideTutorial ()
                        , saveTutorialState (Encode.string "completed")
                        ]
                    )


skipTutorialFrom : TutorialStep -> Model -> ( Model, Cmd Msg )
skipTutorialFrom step model =
    case step of
        SignInStep ->
            if List.isEmpty (Model.activeAccounts model) then
                tutorialNavigateTo AccountsStep model

            else
                tutorialNavigateTo (Tutorial.stepAfterAccounts model) model

        CollaboratorsStep ->
            tutorialNavigateTo FirstExpenseStep model

        FirstExpenseStep ->
            ( { model | tutorialState = TutorialCompleted, tutorialCompletionVisible = True, tutorialExpenseId = Nothing }
            , Cmd.batch
                [ hideTutorial ()
                , saveTutorialState (Encode.string "completed")
                ]
            )

        AccountsStep ->
            ( model, Cmd.none )

        DeleteExpenseStep ->
            ( model, Cmd.none )


tutorialAdvanceCmd : Model -> TutorialState -> TutorialState -> Cmd Msg
tutorialAdvanceCmd model oldState newState =
    case ( oldState, newState ) of
        ( TutorialOpen SignInStep, TutorialOpen step ) ->
            tutorialNavigateCmd model step

        _ ->
            Cmd.none


tutorialNavigateCmd : Model -> TutorialStep -> Cmd Msg
tutorialNavigateCmd model step =
    Cmd.batch
        [ tutorialOpenDisclosureCmd step
        , showTutorialStep (Tutorial.encodeStep model step)
        , focusElement (Tutorial.focusSelector model step)
        ]


tutorialNavigateTo : TutorialStep -> Model -> ( Model, Cmd Msg )
tutorialNavigateTo step model =
    let
        preparedModel =
            Tutorial.prepareStep step { model | tutorialState = TutorialOpen step }
    in
    ( preparedModel
    , tutorialNavigateCmd preparedModel step
    )


tutorialOpenDisclosureCmd : TutorialStep -> Cmd Msg
tutorialOpenDisclosureCmd step =
    Tutorial.openDisclosureIds step
        |> List.map openDisclosure
        |> Cmd.batch


selectSort : SortField -> Model -> Model
selectSort sortField model =
    if model.sortField == sortField then
        { model | sortDirection = toggleSortDirection model.sortDirection }

    else
        { model | sortField = sortField, sortDirection = defaultSortDirection sortField }


toggleSortDirection : SortDirection -> SortDirection
toggleSortDirection sortDirection =
    case sortDirection of
        Ascending ->
            Descending

        Descending ->
            Ascending


defaultSortDirection : SortField -> SortDirection
defaultSortDirection sortField =
    case sortField of
        SortByDate ->
            Descending

        SortByAccount ->
            Ascending

        SortByDescription ->
            Ascending

        SortByExchangeRate ->
            Descending

        SortByPesos ->
            Descending

        SortByDollars ->
            Descending


exportVisibleTable : Export.Format -> Model -> Cmd Msg
exportVisibleTable format model =
    exportTable (Export.tablePayload format model.dateDisplay model.today (Model.activeAccounts model) (Model.visibleExpenses model))


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ authStateChanged AuthStateChanged
        , ledgerLoaded LedgerLoaded
        , expenseIdGenerated ExpenseIdGenerated
        , eventsLoaded EventsLoaded
        , localMigrationPrepared LocalMigrationPrepared
        , tutorialAction TutorialActionReceived
        ]


handleAuthStateChanged : AuthState -> Model -> ( Model, Cmd Msg )
handleAuthStateChanged authState model =
    case authState of
        SignedIn user ->
            let
                ledgerId =
                    case user.acceptedInviteLedgerId of
                        Just invitedLedgerId ->
                            invitedLedgerId

                        Nothing ->
                            if model.currentLedgerId == "" || model.currentLedgerId == localLedgerId then
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
                        , tutorialExpenseId = Nothing
                      }
                    , Cmd.batch
                        [ hideTutorial ()
                        , saveTutorialState (Encode.string "completed")
                        , loadLedgerData (Ledger.encodeLedgerRequest invitedLedgerId)
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
                            [ prepareLocalMigration ()
                            , tutorialAdvanceCmd updatedModel model.tutorialState updatedModel.tutorialState
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
                            [ loadLedgerData (Ledger.encodeLedgerRequest ledgerId)
                            , tutorialAdvanceCmd updatedModel model.tutorialState updatedModel.tutorialState
                            ]
                        )

        SignedOut ->
            let
                signedOutModel =
                    { model
                        | authState = authState
                        , inviteEmail = ""
                        , error = ""
                        , accountError = ""
                        , ledgerError = ""
                    }
                        |> ensureLocalLedger
                        |> Model.ensureSelectedAccount

                tutorialCmd =
                    case signedOutModel.tutorialState of
                        TutorialOpen SignInStep ->
                            tutorialNavigateCmd signedOutModel SignInStep

                        _ ->
                            Cmd.none
            in
            ( signedOutModel
            , Cmd.batch
                [ loadLedgerData (Ledger.encodeLedgerRequest localLedgerId)
                , tutorialCmd
                ]
            )

        AuthUnconfigured ->
            ( { model
                | authState = authState
                , inviteEmail = ""
                , error = ""
                , accountError = ""
                , ledgerError = ""
              }
                |> ensureLocalLedger
                |> Model.ensureSelectedAccount
            , loadLedgerData (Ledger.encodeLedgerRequest localLedgerId)
            )

        _ ->
            ( { model | authState = authState }, Cmd.none )


handleLedgerLoaded : Decode.Value -> Model -> ( Model, Cmd Msg )
handleLedgerLoaded value model =
    case Ledger.decodeLedger value of
        Ok ledger ->
            let
                updatedModel =
                    applyLedgerData ledger model

                advanceCmd =
                    case ( model.tutorialState, updatedModel.tutorialState ) of
                        ( TutorialOpen AccountsStep, TutorialOpen next ) ->
                            tutorialNavigateCmd updatedModel next

                        _ ->
                            Cmd.none
            in
            ( updatedModel, advanceCmd )

        Err error ->
            ( { model | ledgerLoadState = LoadError error, migrationState = NoMigration }, Cmd.none )


handleLocalMigrationPrepared : Decode.Value -> Model -> ( Model, Cmd Msg )
handleLocalMigrationPrepared value model =
    let
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
                        , mergeLocalLedgerToFirestore (Ledger.encodeLedgerRequest ledger.id)
                        )

                    firstLedger :: _ ->
                        let
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
            error =
                Decode.decodeValue (Decode.field "message" Decode.string) value
                    |> Result.withDefault "No se pudo preparar la migración local."
        in
        ( { model | migrationState = NoMigration, ledgerLoadState = LoadError error }, Cmd.none )


localDataExists : Model -> Bool
localDataExists model =
    model.storageMode
        == LocalOnly
        && (not (List.isEmpty model.events)
                || not (List.isEmpty model.accounts)
                || model.ledgerName
                /= localLedgerName
           )


applyLedgerData : Ledger.LedgerData -> Model -> Model
applyLedgerData ledger model =
    let
        accounts =
            Model.activeAccountsFromList ledger.accounts

        form =
            formWithLoadedAccount ledger.lastAccountId accounts model.form

        expenses =
            if List.isEmpty ledger.events then
                Model.activeExpenses ledger.expenses

            else
                Model.activeExpenses (Projector.projectEvents ledger.events)
    in
    { model
        | events = ledger.events
        , expenses = expenses
        , accounts = accounts
        , ledgers = ledger.ledgers
        , currentLedgerId = ledger.currentLedgerId
        , ledgerName = Model.ledgerNameFor ledger.currentLedgerId ledger.ledgers
        , storageMode =
            if ledger.currentLedgerId == localLedgerId then
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
        |> adjustTutorialAfterLedgerLoad model.ledgerLoadState
        |> Model.ensureSelectedAccount


adjustTutorialAfterLedgerLoad : LoadState -> Model -> Model
adjustTutorialAfterLedgerLoad _ model =
    case model.tutorialState of
        TutorialOpen AccountsStep ->
            if not (List.isEmpty (Model.activeAccounts model)) then
                let
                    nextStep =
                        Tutorial.stepAfterAccounts model
                in
                Tutorial.prepareStep nextStep
                    { model
                        | tutorialState = TutorialOpen nextStep
                        , accountError = ""
                    }

            else
                model

        _ ->
            model


tutorialAfterAuth : Model -> TutorialState
tutorialAfterAuth model =
    case model.tutorialState of
        TutorialOpen SignInStep ->
            TutorialOpen (Tutorial.reopenedStep model)

        _ ->
            model.tutorialState


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
