port module Main exposing (main)

import Accounting exposing (FilterWindow(..), SortDirection(..), SortField(..))
import Api.Dolar as Dolar exposing (ExchangeRateStatus(..), OfficialDollar)
import Auth exposing (AuthState(..))
import Browser
import Events exposing (Event)
import Export
import Html exposing (Html, button, div, h1, header, label, main_, option, p, section, select, span, strong, text)
import Html.Attributes exposing (attribute, class, style, type_, value)
import Html.Events exposing (onClick, onInput)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Ledger exposing (LoadState(..))
import Model exposing (MigrationState(..), Model, StorageMode(..), TargetRect, TutorialState(..), TutorialStep(..))
import Projector
import Task
import Time
import Update.Accounts as Accounts
import Update.Ledgers as Ledgers
import Util.Date exposing (DateDisplay(..), dateToIso)
import View.AuthStatus as AuthStatus
import View.ExpenseForm as ExpenseForm
import View.ExpenseTable as ExpenseTable
import View.LedgerAccess as LedgerAccess
import View.LedgerAccounts as LedgerAccounts


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
    | ElementRectReceived Decode.Value


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


port getElementRect : String -> Cmd msg


port openDisclosure : String -> Cmd msg


port elementRectReceived : (Decode.Value -> msg) -> Sub msg


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
                                                 ( { updatedModel | tutorialState = TutorialOpen DeleteExpenseStep }
                                                 , tutorialNavigateCmd updatedModel DeleteExpenseStep
                                                 )

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
                                ( { updatedModel | tutorialState = TutorialOpen CollaboratorsStep, accountError = "" }
                                , tutorialNavigateCmd updatedModel CollaboratorsStep
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
            ( case baseModel.tutorialState of
                TutorialOpen DeleteExpenseStep ->
                    { baseModel | tutorialState = TutorialCompleted, tutorialCompletionVisible = True }

                _ ->
                    baseModel
            , Cmd.batch
                [ appendEvent
                    (Encode.object
                        [ ( "ledgerId", Encode.string model.currentLedgerId )
                        , ( "event", Events.eventEncoder event )
                        ]
                    )
                , saveTutorialState (Encode.string "completed")
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
                    let
                        prev =
                            previousTutorialStep step
                    in
                    ( { model | tutorialState = TutorialOpen prev }
                    , tutorialNavigateCmd model prev
                    )

                _ ->
                    ( model, Cmd.none )

        TutorialSkip ->
            ( { model | tutorialState = TutorialDismissed }
            , saveTutorialState (Encode.string "dismissed")
            )

        TutorialFinish ->
            ( { model | tutorialState = TutorialCompleted, tutorialCompletionVisible = True }
            , saveTutorialState (Encode.string "completed")
            )

        ReopenTutorial ->
            let
                step =
                    reopenedTutorialStep model
            in
            ( { model | tutorialState = TutorialOpen step, tutorialCompletionVisible = False }
            , Cmd.batch
                [ saveTutorialState (Encode.string "")
                , tutorialNavigateCmd model step
                ]
            )

        DismissTutorialCompletion ->
            ( { model | tutorialCompletionVisible = False }, Cmd.none )

        ElementRectReceived value ->
            case Decode.decodeValue tutorialTargetRectDecoder value of
                Ok rect ->
                    ( { model | tutorialTargetRect = Just rect }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )


payloadCmd : (Encode.Value -> Cmd Msg) -> Maybe Encode.Value -> Cmd Msg
payloadCmd toCmd payload =
    payload
        |> Maybe.map toCmd
        |> Maybe.withDefault Cmd.none


view : Model -> Html Msg
view model =
    let
        rows =
            Model.visibleExpenses model

        isTutorialOpen =
            case model.tutorialState of
                TutorialOpen _ ->
                    True

                _ ->
                    False

        mainContent =
            [ reopenTutorialButton model
            , tutorialCompletionBanner model
            , migrationPrompt model
            , localRiskBanner model
                , div [ class "layout" ]
                    [ div [ class "input-area" ]
                        [ ExpenseForm.view
                            { form = model.form
                            , accounts = Model.activeAccounts model
                            , exchangeRate = model.exchangeRate
                            , exchangeRateStatus = model.exchangeRateStatus
                            , zone = model.zone
                            , error = model.error
                            , onDescription = UpdateDescription
                            , onAmount = UpdateAmount
                            , onAccount = UpdateAccount
                            , onCreateAccount = OpenAccountTool
                            , onCurrency = UpdateCurrency
                            , onDate = UpdateDate
                            , onMovementType = UpdateMovementType
                            , onSubmit = AddExpense
                            , onCancel = CancelEdit
                            }
                        ]
                    , div [ class "admin-area" ]
                        [ adminArea model
                        ]
                    , div [ class "content-stack" ]
                        [ ExpenseTable.view
                            { expenses = rows
                            , accounts = Model.activeAccounts model
                            , filterWindow = model.filterWindow
                            , hiddenAccountIds = model.hiddenAccountIds
                            , dateDisplay = model.dateDisplay
                            , displayCurrency = model.displayCurrency
                            , sortField = model.sortField
                            , sortDirection = model.sortDirection
                            , onSelectFilter = SelectFilter
                            , onToggleAccount = ToggleAccountFilter
                            , onSelectDateDisplay = SelectDateDisplay
                            , onSelectDisplayCurrency = SelectDisplayCurrency
                            , onSelectSort = SelectSort
                            , onExportCsv = ExportCsv
                            , onExportXlsx = ExportXlsx
                            , onDelete = DeleteExpense
                            , onEdit = EditExpense
                            }
                        ]
                    ]
                ]
    in
    div [ class "app" ]
        [ header [ class "topbar" ]
            [ div [ class "topbar__inner" ]
                [ div [ class "topbar__content" ]
                    [ div []
                        [ h1 [] [ text "ContabilizAR" ] ]
                    , div [ class "topbar__actions" ]
                        [ if isTutorialOpen then
                            text ""

                          else
                            button [ class "topbar-setup-button", type_ "button", onClick ReopenTutorial ]
                                [ text "Configuracion inicial" ]
                        , AuthStatus.view
                            { authState = model.authState
                            , ledgerLoadState = model.ledgerLoadState
                            , onSignIn = SignInWithGoogle
                            , onSignOut = SignOut
                            }
                        ]
                    ]
                ]
            ]
        , main_ [] mainContent
        , tutorialView model
        ]


tutorialCompletionBanner : Model -> Html Msg
tutorialCompletionBanner model =
    if model.tutorialCompletionVisible then
        section [ class "tutorial-done-banner" ]
            [ strong [] [ text "Listo" ]
            , span [] [ text "Ya puedes empezar a registrar movimientos." ]
            , button [ type_ "button", onClick DismissTutorialCompletion ] [ text "Cerrar" ]
            ]

    else
        text ""


reopenTutorialButton : Model -> Html Msg
reopenTutorialButton model =
    case model.tutorialState of
        TutorialOpen _ ->
            text ""

        _ ->
            section [ class "setup-shortcut" ]
                [ button [ class "setup-shortcut__button", type_ "button", onClick ReopenTutorial ]
                    [ text "Abrir configuracion inicial" ]
                ]


tutorialView : Model -> Html Msg
tutorialView model =
    case model.tutorialState of
        TutorialOpen step ->
            div [ class "tutorial-overlay" ]
                [ case model.tutorialTargetRect of
                    Just rect ->
                        div
                            [ class "tutorial-spotlight"
                            , style "top" (String.fromFloat rect.top ++ "px")
                            , style "left" (String.fromFloat rect.left ++ "px")
                            , style "width" (String.fromFloat rect.width ++ "px")
                            , style "height" (String.fromFloat rect.height ++ "px")
                            ]
                            []

                    Nothing ->
                        div [ class "tutorial-backdrop" ] []
                , div
                    (class "tutorial-tooltip" :: tutorialTooltipPosition model.tutorialTargetRect)
                    [ p [] [ text (tutorialStepText step) ]
                    , div [ class "tutorial-tooltip__actions" ]
                        ([ if step == SignInStep then
                            text ""

                           else
                            button [ class "tutorial-tooltip__back", type_ "button", onClick TutorialBack ] [ text "Atras" ]
                         ]
                            ++ (if step == DeleteExpenseStep then
                                    [ button [ class "primary", type_ "button", onClick TutorialFinish ] [ text "Finalizar" ] ]

                                else
                                    [ button [ class "primary", type_ "button", onClick TutorialNext ] [ text "Siguiente" ] ]
                               )
                            ++ [ button [ class "tutorial-tooltip__skip", type_ "button", onClick TutorialSkip ] [ text "Saltar" ] ]
                        )
                    ]
                ]

        _ ->
            text ""


tutorialTooltipPosition : Maybe TargetRect -> List (Html.Attribute Msg)
tutorialTooltipPosition maybeRect =
    case maybeRect of
        Just rect ->
            [ style "top" (String.fromFloat (rect.bottom + 8) ++ "px")
            , style "left" (String.fromFloat rect.left ++ "px")
            ]

        Nothing ->
            [ style "top" "50%"
            , style "left" "50%"
            ]


tutorialStepText : TutorialStep -> String
tutorialStepText step =
    case step of
        SignInStep ->
            "Para empezar, inicia sesion con Google. Si no quieres sincronizar, puedes saltar este paso."

        AccountsStep ->
            "Crea una cuenta para registrar movimientos. Dale un nombre y agregala."

        CollaboratorsStep ->
            "Invita a alguien por email para trabajar juntos. Tambien puedes hacerlo despues."

        FirstExpenseStep ->
            "Registra tu primer movimiento. Completa los campos y presiona \"Agregar\"."

        DeleteExpenseStep ->
            "Puedes eliminar o editar movimientos. Prueba a eliminar este."


tutorialTargetSelector : Model -> TutorialStep -> String
tutorialTargetSelector model step =
    case step of
        SignInStep ->
            "[data-tutorial=\"sign-in\"]"

        AccountsStep ->
            "[data-tutorial=\"account-name\"]"

        CollaboratorsStep ->
            "[data-tutorial=\"invite-email\"]"

        FirstExpenseStep ->
            "[data-tutorial=\"description\"]"

        DeleteExpenseStep ->
            case List.head (Model.activeExpenses model.expenses) of
                Just expense ->
                    "[data-tutorial=\"delete-" ++ expense.id ++ "\"]"

                Nothing ->
                    "[data-tutorial=\"description\"]"


tutorialTargetRectDecoder : Decode.Decoder TargetRect
tutorialTargetRectDecoder =
    Decode.field "rect" <|
        Decode.map6 TargetRect
            (Decode.field "top" Decode.float)
            (Decode.field "right" Decode.float)
            (Decode.field "bottom" Decode.float)
            (Decode.field "left" Decode.float)
            (Decode.field "width" Decode.float)
            (Decode.field "height" Decode.float)


advanceTutorialFrom : TutorialStep -> Model -> ( Model, Cmd Msg )
advanceTutorialFrom step model =
    case rawNextStep step of
        Just nextStep ->
            ( { model | tutorialState = TutorialOpen nextStep }
            , tutorialNavigateCmd model nextStep
            )

        Nothing ->
            ( { model | tutorialState = TutorialCompleted, tutorialCompletionVisible = True }
            , saveTutorialState (Encode.string "completed")
            )


rawNextStep : TutorialStep -> Maybe TutorialStep
rawNextStep step =
    case step of
        SignInStep ->
            Just AccountsStep

        AccountsStep ->
            Just CollaboratorsStep

        CollaboratorsStep ->
            Just FirstExpenseStep

        FirstExpenseStep ->
            Just DeleteExpenseStep

        DeleteExpenseStep ->
            Nothing


previousTutorialStep : TutorialStep -> TutorialStep
previousTutorialStep step =
    case step of
        SignInStep ->
            SignInStep

        AccountsStep ->
            SignInStep

        CollaboratorsStep ->
            AccountsStep

        FirstExpenseStep ->
            CollaboratorsStep

        DeleteExpenseStep ->
            FirstExpenseStep


reopenedTutorialStep : Model -> TutorialStep
reopenedTutorialStep model =
    if List.isEmpty (Model.activeAccounts model) then
        AccountsStep

    else
        CollaboratorsStep


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
        , getElementRect (tutorialTargetSelector model step)
        ]


tutorialOpenDisclosureCmd : TutorialStep -> Cmd Msg
tutorialOpenDisclosureCmd step =
    case step of
        AccountsStep ->
            Cmd.batch
                [ openDisclosure "admin-tool"
                , openDisclosure "accounts-tool"
                ]

        CollaboratorsStep ->
            Cmd.batch
                [ openDisclosure "admin-tool"
                , openDisclosure "members-tool"
                ]

        _ ->
            Cmd.none


migrationPrompt : Model -> Html Msg
migrationPrompt model =
    case model.migrationState of
        NoMigration ->
            text ""

        PreparingMigration ->
            section [ class "migration-panel" ]
                [ strong [] [ text "Preparando sincronizacion" ]
                , p [] [ text "Estamos revisando tus libros de Firestore antes de subir los datos locales." ]
                ]

        UploadingMigration _ ->
            section [ class "migration-panel" ]
                [ strong [] [ text "Subiendo datos locales" ]
                , p [] [ text "Estamos agregando tus cuentas y movimientos locales al libro elegido." ]
                ]

        ChoosingMigration ledgers selectedLedgerId ->
            section [ class "migration-panel" ]
                [ strong [] [ text "Subir datos locales" ]
                , p [] [ text "Encontramos mas de un libro disponible. Elige donde quieres mergear las cuentas y movimientos guardados en este navegador." ]
                , label []
                    [ text "Libro destino"
                    , select [ value selectedLedgerId, onInput SelectMigrationLedger ]
                        (List.map migrationLedgerOption ledgers)
                    ]
                , div [ class "migration-panel__actions" ]
                    [ button [ class "primary", type_ "button", onClick ConfirmLocalMigration ] [ text "Subir datos locales" ]
                    , button [ class "cancel-button", type_ "button", onClick SkipLocalMigration ] [ text "Ahora no" ]
                    ]
                ]


migrationLedgerOption : Ledger.LedgerSummary -> Html Msg
migrationLedgerOption ledger =
    option [ value ledger.id ] [ text ledger.name ]


localRiskBanner : Model -> Html Msg
localRiskBanner model =
    case model.authState of
        SignedIn _ ->
            text ""

        _ ->
            if model.storageMode == LocalOnly then
                let
                    hasLocalData =
                        not (List.isEmpty model.events)
                            || not (List.isEmpty model.accounts)
                            || model.ledgerName
                            /= localLedgerName
                in
                section [ class "local-risk" ]
                    [ strong [] [ text "Modo local" ]
                    , span []
                        [ text
                            (if hasLocalData then
                                "Tus datos estan guardados solo en este navegador. Inicia sesion con Google para respaldo y sincronizacion."

                             else
                                "Puedes usar la app sin Google. Los datos locales pueden perderse si se borra el navegador o cambias de dispositivo."
                            )
                        ]
                    ]

            else
                text ""


adminArea : Model -> Html Msg
adminArea model =
    section [ class "panel admin-panel" ]
        [ Html.details [ class "admin-disclosure", Html.Attributes.id "admin-tool" ]
            [ Html.summary [ class "admin-disclosure__summary" ]
                [ span [] [ text "Configuracion del libro" ]
                , strong [] [ text "Administrar" ]
                ]
            , div [ class "admin-disclosure__content" ]
                [ LedgerAccess.view
                    { authState = model.authState
                    , ledgers = model.ledgers
                    , currentLedgerId = model.currentLedgerId
                    , ledgerName = model.ledgerName
                    , inviteEmail = model.inviteEmail
                    , error = model.ledgerError
                    , onSelectLedger = SelectLedger
                    , onLedgerName = UpdateLedgerName
                    , onSaveLedgerName = SaveLedgerName
                    , onInviteEmail = UpdateInviteEmail
                    , onInvite = InviteGuest
                    , onRemoveGuest = RemoveGuest
                    }
                , LedgerAccounts.view
                    { accounts = Model.activeAccounts model
                    , newAccountName = model.newAccountName
                    , error = model.accountError
                    , onName = UpdateNewAccountName
                    , onAdd = AddAccount
                    , onDelete = DeleteAccount
                    }
                ]
            ]
        ]


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
        , elementRectReceived ElementRectReceived
        ]


handleAuthStateChanged : AuthState -> Model -> ( Model, Cmd Msg )
handleAuthStateChanged authState model =
    case authState of
        SignedIn user ->
            let
                ledgerId =
                    if model.currentLedgerId == "" || model.currentLedgerId == localLedgerId then
                        user.uid

                    else
                        model.currentLedgerId
            in
            let
                newTutorialState =
                    tutorialAfterAuth model
            in
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
                    , tutorialState = newTutorialState
                   }
                , Cmd.batch
                    [ prepareLocalMigration ()
                    , tutorialAdvanceCmd model model.tutorialState newTutorialState
                    ]
                )

            else
                ( { model
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
                , Cmd.batch
                    [ loadLedgerData (Ledger.encodeLedgerRequest ledgerId)
                    , tutorialAdvanceCmd model model.tutorialState newTutorialState
                    ]
                )

        SignedOut ->
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
            ( applyLedgerData ledger model, Cmd.none )

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
    model


tutorialAfterAuth : Model -> TutorialState
tutorialAfterAuth model =
    case model.tutorialState of
        TutorialOpen SignInStep ->
            TutorialOpen (reopenedTutorialStep model)

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
