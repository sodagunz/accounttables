port module Main exposing (Msg, main)

import Accounting exposing (FilterWindow, SortField)
import Api.Dolar exposing (ExchangeRateStatus(..))
import Auth
import Browser
import Config
import Export
import Flags
import Html exposing (Html)
import InvoiceReport
import Json.Decode as Decode
import Json.Encode as Encode
import Ledger exposing (LoadState(..))
import Model exposing (MigrationState(..), Model, TutorialState(..), TutorialStep(..))
import Task
import Time
import Tutorial
import Update.Accounts as Accounts
import Update.Auth as AuthUpdate
import Update.LedgerData as LedgerData
import Update.Ledgers as Ledgers
import Update.Movements as Movements
import Update.Sorting as Sorting
import Util.Date exposing (DateDisplay(..), dateToIso, formatDate)
import View.App as AppView


type Msg
    = GotToday Time.Zone Time.Posix
    | UpdateDescription String
    | UpdateAmount String
    | UpdateAccount String
    | UpdateCurrency String
    | UpdateDate String
    | UpdateMovementType Accounting.MovementType
    | UpdateRelatedToInvoice Bool
    | UpdateDocumentNumber String
    | ToggleAllocationTarget String Bool
    | OpenAccountTool
    | SelectFilter FilterWindow
    | SelectDateDisplay DateDisplay
    | SelectDisplayCurrency Accounting.Currency
    | ToggleShowInputAmountColumn
    | ToggleShowExchangeRateColumn
    | SelectSort SortField
    | ExportCsv
    | ExportXlsx
    | ExportInvoicesCsv
    | ExportInvoicesXlsx
    | SignInWithGoogle
    | SignOut
    | AuthStateChanged Decode.Value
    | LedgerLoaded Decode.Value
    | ExchangeRateLoaded Decode.Value
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
    | ReopenTutorial
    | SelectViewMode Model.ViewMode
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


port saveFilterWindowSelection : String -> Cmd msg


port appendEvent : Encode.Value -> Cmd msg


port loadExchangeRate : Encode.Value -> Cmd msg


port focusAccountTool : () -> Cmd msg


port eventsLoaded : (Decode.Value -> msg) -> Sub msg


port ledgerLoaded : (Decode.Value -> msg) -> Sub msg


port exchangeRateLoaded : (Decode.Value -> msg) -> Sub msg


port prepareLocalMigration : () -> Cmd msg


port localMigrationPrepared : (Decode.Value -> msg) -> Sub msg


port mergeLocalLedgerToFirestore : Encode.Value -> Cmd msg


port saveTutorialState : Encode.Value -> Cmd msg


port showTutorialStep : Encode.Value -> Cmd msg


port openDisclosure : String -> Cmd msg


port focusElement : String -> Cmd msg


port hideTutorial : () -> Cmd msg


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
        model : Model
        model =
            Flags.modelFromFlags flags

        baseCmds : List (Cmd Msg)
        baseCmds =
            [ Task.perform identity (Task.map2 GotToday Time.here Time.now)
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
                today : String
                today =
                    dateToIso zone posix

                updatedModel : Model
                updatedModel =
                    { model
                        | form = Accounting.setDate today model.form
                        , today = today
                        , zone = zone
                        , exchangeRateDate = today
                        , exchangeRateStatus = LoadingRate
                    }
                        |> Model.ensureSelectedAccount
            in
            ( updatedModel
            , requestExchangeRate updatedModel.currentLedgerId today
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
            let
                updatedModel : Model
                updatedModel =
                    { model
                        | form = Accounting.setDate date model.form
                        , exchangeRateDate = date
                        , exchangeRateStatus = LoadingRate
                    }
            in
            if date == "" then
                ( updatedModel, Cmd.none )

            else
                ( updatedModel, requestExchangeRate updatedModel.currentLedgerId date )

        UpdateMovementType movementType ->
            ( { model | form = Accounting.setMovementType movementType model.form }, Cmd.none )

        UpdateRelatedToInvoice relatedToInvoice ->
            ( { model | form = Accounting.setRelatedToInvoice relatedToInvoice model.form }, Cmd.none )

        UpdateDocumentNumber documentNumber ->
            ( { model | form = Accounting.setDocumentNumber documentNumber model.form }, Cmd.none )

        ToggleAllocationTarget targetId selected ->
            ( { model | form = Accounting.toggleAllocationTarget targetId selected model.form }, Cmd.none )

        OpenAccountTool ->
            ( { model | accountError = "" }, focusAccountTool () )

        SelectFilter filterWindow ->
            ( { model | filterWindow = filterWindow }
            , saveFilterWindowSelection (Accounting.filterWindowToString filterWindow)
            )

        SelectDateDisplay dateDisplay ->
            ( { model | dateDisplay = dateDisplay }, Cmd.none )

        SelectDisplayCurrency currency ->
            ( { model | displayCurrency = currency }, Cmd.none )

        ToggleShowInputAmountColumn ->
            ( { model | showInputAmountColumn = not model.showInputAmountColumn }, Cmd.none )

        ToggleShowExchangeRateColumn ->
            ( { model | showExchangeRateColumn = not model.showExchangeRateColumn }, Cmd.none )

        SelectSort sortField ->
            ( Sorting.select sortField model, Cmd.none )

        ExportCsv ->
            ( model, exportVisibleTable Export.Csv model )

        ExportXlsx ->
            ( model, exportVisibleTable Export.Xlsx model )

        ExportInvoicesCsv ->
            ( model, exportInvoices Export.Csv model )

        ExportInvoicesXlsx ->
            ( model, exportInvoices Export.Xlsx model )

        SignInWithGoogle ->
            ( model, signInWithGoogle () )

        SignOut ->
            ( model, signOutUser () )

        AuthStateChanged value ->
            AuthUpdate.handleState authUpdateConfig (Auth.decodeAuthState value) model

        LedgerLoaded value ->
            LedgerData.handleLedgerLoaded ledgerDataConfig value model

        ExchangeRateLoaded value ->
            handleExchangeRateLoaded value model

        AddMovement ->
            case ensureExchangeRateReady model of
                Ok () ->
                    Movements.requestId movementsConfig model

                Err error ->
                    ( { model | error = error }, Cmd.none )

        MovementIdGenerated value ->
            Movements.handleGeneratedId movementsConfig value model

        UpdateNewAccountName name ->
            ( { model | newAccountName = name }, Cmd.none )

        AddAccount ->
            let
                addResult : ( Model, Maybe Encode.Value )
                addResult =
                    Accounts.add model

                updatedModel : Model
                updatedModel =
                    Tuple.first addResult

                payload : Maybe Encode.Value
                payload =
                    Tuple.second addResult

                finalResult : ( Model, Cmd Msg )
                finalResult =
                    case updatedModel.tutorialState of
                        TutorialOpen AccountsStep ->
                            if not (List.isEmpty (Model.activeAccounts updatedModel)) then
                                let
                                    nextAccountsStep : TutorialStep
                                    nextAccountsStep =
                                        Tutorial.stepAfterAccounts updatedModel

                                    nextModel : Model
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

                finalModel : Model
                finalModel =
                    Tuple.first finalResult

                advanceCmd : Cmd Msg
                advanceCmd =
                    Tuple.second finalResult
            in
            ( finalModel, Cmd.batch [ payloadCmd saveAccount payload, advanceCmd ] )

        DeleteAccount accountId ->
            let
                deleteResult : ( Model, Maybe Encode.Value )
                deleteResult =
                    Accounts.delete accountId model
            in
            ( Tuple.first deleteResult, payloadCmd deleteAccount (Tuple.second deleteResult) )

        SelectLedger ledgerId ->
            ( Ledgers.select ledgerId model
            , loadLedgerData (Ledger.encodeLedgerRequest ledgerId)
            )

        UpdateLedgerName name ->
            ( { model | ledgerName = name }, Cmd.none )

        SaveLedgerName ->
            let
                renameResult : ( Model, Maybe Encode.Value )
                renameResult =
                    Ledgers.rename model
            in
            ( Tuple.first renameResult, payloadCmd updateLedgerName (Tuple.second renameResult) )

        UpdateInviteEmail email ->
            ( { model | inviteEmail = email }, Cmd.none )

        InviteGuest ->
            let
                inviteResult : ( Model, Maybe Encode.Value )
                inviteResult =
                    Ledgers.inviteGuest model
            in
            ( Tuple.first inviteResult, payloadCmd inviteLedgerGuest (Tuple.second inviteResult) )

        RemoveGuest uid ->
            let
                removeResult : ( Model, Maybe Encode.Value )
                removeResult =
                    Ledgers.removeGuest uid model
            in
            ( Tuple.first removeResult, payloadCmd removeLedgerGuest (Tuple.second removeResult) )

        ToggleAccountFilter accountId ->
            let
                hidden : List String
                hidden =
                    model.hiddenAccountIds

                updatedHidden : List String
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
            case List.head (List.filter (\movement -> movement.id == movementId) model.expenses) of
                Just movement ->
                    let
                        ( updatedModel, cmd ) =
                            Movements.edit movementId model
                    in
                    ( { updatedModel
                        | exchangeRate = movement.exchangeRate
                        , exchangeRateDate = movement.date
                        , exchangeRateStatus = LoadedRate (loadedExchangeRateMessage movement.date)
                      }
                    , cmd
                    )

                Nothing ->
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

        ReopenTutorial ->
            let
                step : TutorialStep
                step =
                    Tutorial.reopenedStep model

                reopenResult : ( Model, Cmd Msg )
                reopenResult =
                    Tutorial.tutorialNavigateTo tutorialConfig step { model | tutorialCompletionVisible = False, tutorialMovementId = Nothing }
            in
            ( Tuple.first reopenResult
            , Cmd.batch
                [ saveTutorialState (Encode.string "")
                , Tuple.second reopenResult
                ]
            )

        DismissTutorialCompletion ->
            ( { model | tutorialCompletionVisible = False }, Cmd.none )

        SelectViewMode viewMode ->
            ( { model | viewMode = viewMode }, Cmd.none )

        TutorialActionReceived value ->
            Tutorial.handleTutorialAction tutorialConfig value model


type alias ExchangeRatePayload =
    { status : String
    , date : String
    , sale : Maybe Float
    , source : Maybe String
    , message : Maybe String
    }


exchangeRatePayloadDecoder : Decode.Decoder ExchangeRatePayload
exchangeRatePayloadDecoder =
    Decode.map5 ExchangeRatePayload
        (Decode.field "status" Decode.string)
        (Decode.field "date" Decode.string)
        (Decode.maybe (Decode.field "sale" Decode.float))
        (Decode.maybe (Decode.field "source" Decode.string))
        (Decode.maybe (Decode.field "message" Decode.string))


requestExchangeRate : String -> String -> Cmd Msg
requestExchangeRate ledgerId date =
    loadExchangeRate
        (Encode.object
            [ ( "ledgerId", Encode.string ledgerId )
            , ( "date", Encode.string date )
            , ( "casa", Encode.string "bolsa" )
            ]
        )


handleExchangeRateLoaded : Decode.Value -> Model -> ( Model, Cmd Msg )
handleExchangeRateLoaded value model =
    case Decode.decodeValue exchangeRatePayloadDecoder value of
        Ok payload ->
            if payload.date /= model.form.date then
                ( model, Cmd.none )

            else
                case ( payload.status, payload.sale ) of
                    ( "loaded", Just sale ) ->
                        ( { model
                            | exchangeRate = sale
                            , exchangeRateDate = payload.date
                            , exchangeRateStatus = LoadedRate (loadedExchangeRateMessage payload.date)
                            , error = ""
                          }
                        , Cmd.none
                        )

                    ( "error", _ ) ->
                        ( { model
                            | exchangeRateDate = payload.date
                            , exchangeRateStatus = FailedRate (payload.message |> Maybe.withDefault (failedExchangeRateMessage payload.date))
                          }
                        , Cmd.none
                        )

                    _ ->
                        ( { model
                            | exchangeRateDate = payload.date
                            , exchangeRateStatus = FailedRate (failedExchangeRateMessage payload.date)
                          }
                        , Cmd.none
                        )

        Err error ->
            ( { model | exchangeRateStatus = FailedRate (Decode.errorToString error) }, Cmd.none )


loadedExchangeRateMessage : String -> String
loadedExchangeRateMessage date =
    "Bolsa del " ++ formatDate NumericDate date


failedExchangeRateMessage : String -> String
failedExchangeRateMessage date =
    "No se pudo cargar la cotización bolsa del " ++ formatDate NumericDate date ++ "."


ensureExchangeRateReady : Model -> Result String ()
ensureExchangeRateReady model =
    if model.form.date == "" then
        Ok ()

    else if model.exchangeRateDate /= model.form.date then
        Err "Todavía no está lista la cotización bolsa para la fecha elegida."

    else
        case model.exchangeRateStatus of
            LoadingRate ->
                Err "Espera a que cargue la cotización bolsa para la fecha elegida."

            FailedRate message ->
                Err message

            LoadedRate _ ->
                Ok ()


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
    , relatedToInvoice = UpdateRelatedToInvoice
    , documentNumber = UpdateDocumentNumber
    , allocationTarget = ToggleAllocationTarget
    , submitMovement = AddMovement
    , cancelEdit = CancelEdit
    , selectFilter = SelectFilter
    , toggleAccountFilter = ToggleAccountFilter
    , selectDateDisplay = SelectDateDisplay
    , selectDisplayCurrency = SelectDisplayCurrency
    , toggleShowInputAmountColumn = ToggleShowInputAmountColumn
    , toggleShowExchangeRateColumn = ToggleShowExchangeRateColumn
    , selectSort = SelectSort
    , exportCsv = ExportCsv
    , exportXlsx = ExportXlsx
    , exportInvoicesCsv = ExportInvoicesCsv
    , exportInvoicesXlsx = ExportInvoicesXlsx
    , selectViewMode = SelectViewMode
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
    let
        invoiceRows : List Accounting.Movement
        invoiceRows =
            Model.visibleInvoiceMovements model

        relatedCashflows : List Accounting.Movement
        relatedCashflows =
            Model.visibleInvoiceRelatedCashflows model

        payable : Accounting.MoneyTotal
        payable =
            InvoiceReport.build (Model.activeMovements model.expenses) invoiceRows relatedCashflows
                |> .summary
                |> .payable
    in
    exportTable (Export.tablePayload format model.dateDisplay model.today (Model.activeAccounts model) (Model.visibleCashflowMovements model) payable)


exportInvoices : Export.Format -> Model -> Cmd Msg
exportInvoices format model =
    exportTable (Export.invoiceTablePayload format model.dateDisplay model.today (Model.activeMovements model.expenses) (Model.visibleInvoiceMovements model) (Model.visibleInvoiceRelatedCashflows model))


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ authStateChanged AuthStateChanged
        , ledgerLoaded LedgerLoaded
        , exchangeRateLoaded ExchangeRateLoaded
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
