port module Main exposing (main)

import Accounting exposing (FilterWindow(..), SortDirection(..), SortField(..))
import Api.Dolar as Dolar exposing (ExchangeRateStatus(..), OfficialDollar)
import Auth exposing (AuthState(..))
import Browser
import Events exposing (Event)
import Export
import Html exposing (Html, button, div, h1, header, label, main_, option, p, section, select, span, strong, text)
import Html.Attributes exposing (class, type_, value)
import Html.Events exposing (onClick, onInput)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Ledger exposing (LoadState(..))
import Model exposing (MigrationState(..), Model, StorageMode(..), WizardState(..), WizardStep(..))
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
    | WizardNext
    | WizardBack
    | WizardSkip
    | WizardFinish
    | ReopenWizard
    | DismissWizardCompletion


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


port saveWizardState : Encode.Value -> Cmd msg


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
    ( modelFromFlags flags
    , Cmd.batch
        [ Task.perform identity (Task.map2 GotToday Time.here Time.now)
        , Dolar.fetchOfficialDollar GotExchangeRate
        ]
    )


modelFromFlags : Decode.Value -> Model
modelFromFlags flags =
    let
        wizardState =
            decodeWizardStateFromFlags flags

        initialModel =
            Model.initial

        baseModel =
            { initialModel | wizardState = wizardState }

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


decodeWizardStateFromFlags : Decode.Value -> WizardState
decodeWizardStateFromFlags flags =
    case Decode.decodeValue (Decode.field "wizardState" Decode.string) flags of
        Ok "dismissed" ->
            WizardDismissed

        Ok "completed" ->
            WizardCompleted

        _ ->
            WizardOpen WelcomeStep


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
                            ( { updatedModel
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
            in
            ( updatedModel, payloadCmd saveAccount payload )

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
            in
            ( { model
                | events = event :: model.events
                , expenses = Model.activeExpenses updatedExpenses
              }
            , appendEvent
                (Encode.object
                    [ ( "ledgerId", Encode.string model.currentLedgerId )
                    , ( "event", Events.eventEncoder event )
                    ]
                )
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

        WizardNext ->
            case model.wizardState of
                WizardOpen step ->
                    ( advanceWizardFrom step model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        WizardBack ->
            case model.wizardState of
                WizardOpen step ->
                    ( { model | wizardState = WizardOpen (previousWizardStep model step) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        WizardSkip ->
            ( { model | wizardState = WizardDismissed }
            , saveWizardState (Encode.string "dismissed")
            )

        WizardFinish ->
            ( { model | wizardState = WizardCompleted, wizardCompletionVisible = True }
            , saveWizardState (Encode.string "completed")
            )

        ReopenWizard ->
            ( { model | wizardState = WizardOpen WelcomeStep, wizardCompletionVisible = False }
            , saveWizardState (Encode.string "")
            )

        DismissWizardCompletion ->
            ( { model | wizardCompletionVisible = False }, Cmd.none )


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
    in
    div [ class "app" ]
        [ header [ class "topbar" ]
            [ div [ class "topbar__inner" ]
                [ div [ class "topbar__content" ]
                    [ div []
                        [ h1 [] [ text "ContabilizAR" ] ]
                    , div [ class "topbar__actions" ]
                        [ button [ class "topbar-setup-button", type_ "button", onClick ReopenWizard ]
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
        , main_ []
            [ wizardView model
            , reopenWizardButton model
            , wizardCompletionBanner model
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
        ]


wizardCompletionBanner : Model -> Html Msg
wizardCompletionBanner model =
    if model.wizardCompletionVisible then
        section [ class "wizard-done-banner" ]
            [ strong [] [ text "Listo" ]
            , span [] [ text "Ya puedes empezar a registrar movimientos." ]
            , button [ type_ "button", onClick DismissWizardCompletion ] [ text "Cerrar" ]
            ]

    else
        text ""


reopenWizardButton : Model -> Html Msg
reopenWizardButton model =
    case model.wizardState of
        WizardOpen _ ->
            text ""

        _ ->
            section [ class "setup-shortcut" ]
                [ button [ class "setup-shortcut__button", type_ "button", onClick ReopenWizard ]
                    [ text "Abrir configuracion inicial" ]
                ]


wizardView : Model -> Html Msg
wizardView model =
    case model.wizardState of
        WizardOpen step ->
            section [ class "wizard-panel" ]
                [ div [ class "wizard-panel__header" ]
                    [ span [ class "wizard-panel__step" ] [ text (wizardStepLabel step) ]
                    , button [ class "wizard-panel__skip", type_ "button", onClick WizardSkip ] [ text "Saltar" ]
                    ]
                , div [ class "wizard-panel__body" ] (wizardStepContent model step)
                , div [ class "wizard-panel__actions" ]
                    ([ if step == WelcomeStep then
                        text ""

                       else
                        button [ class "cancel-button", type_ "button", onClick WizardBack ] [ text "Atras" ]
                     ]
                        ++ wizardPrimaryAction model step
                    )
                ]

        _ ->
            text ""


wizardPrimaryAction : Model -> WizardStep -> List (Html Msg)
wizardPrimaryAction model step =
    case step of
        WelcomeStep ->
            []

        AccountsStep ->
            if List.isEmpty (Model.activeAccounts model) then
                []

            else
                [ button [ class "primary", type_ "button", onClick WizardNext ] [ text "Continuar" ] ]

        CollaboratorsStep ->
            [ button [ class "primary", type_ "button", onClick WizardFinish ] [ text "Finalizar" ] ]


wizardStepContent : Model -> WizardStep -> List (Html Msg)
wizardStepContent model step =
    case step of
        WelcomeStep ->
            [ h1 [] [ text "Configura tu libro" ]
            , p [] [ text "Puedes iniciar sesion con Google para sincronizar o trabajar solo en este navegador bajo tu propio riesgo." ]
            , div [ class "wizard-panel__inline-actions" ]
                [ button [ class "primary", type_ "button", onClick SignInWithGoogle ] [ text "Ingresar con Google" ]
                , button [ class "cancel-button", type_ "button", onClick WizardNext ] [ text "Usar solo en este dispositivo" ]
                ]
            ]

        AccountsStep ->
            [ h1 [] [ text "Crea tus cuentas" ]
            , p []
                [ text
                    (if List.isEmpty (Model.activeAccounts model) then
                        "Necesitas al menos una cuenta para registrar movimientos."

                     else
                        "Estas son las cuentas que ya creaste. Puedes continuar o agregar otra."
                    )
                ]
            , label []
                [ text "Nueva cuenta"
                , Html.input
                    [ type_ "text"
                    , value model.newAccountName
                    , onInput UpdateNewAccountName
                    ]
                    []
                ]
            , div [ class "wizard-panel__inline-actions" ]
                [ button [ class "primary", type_ "button", onClick AddAccount ] [ text "Agregar cuenta" ]
                , button [ class "cancel-button", type_ "button", onClick OpenAccountTool ] [ text "Abrir cuentas" ]
                ]
            , wizardAccountList model
            , p [ class "error" ] [ text model.accountError ]
            ]

        CollaboratorsStep ->
            case model.authState of
                SignedIn _ ->
                    [ h1 [] [ text "Invita colaboradores" ]
                    , p [] [ text "Si trabajas con alguien mas, puedes invitarlo por email. Tambien puedes hacerlo despues desde Miembros." ]
                    , label []
                        [ text "Email"
                        , Html.input
                            [ type_ "email"
                            , value model.inviteEmail
                            , onInput UpdateInviteEmail
                            ]
                            []
                        ]
                    , button [ class "primary", type_ "button", onClick InviteGuest ] [ text "Invitar" ]
                    , wizardCollaboratorList model
                    , p [ class "error" ] [ text model.ledgerError ]
                    ]

                _ ->
                    [ h1 [] [ text "Colaboradores" ]
                    , p [] [ text "Las invitaciones necesitan Google y Firestore. Puedes seguir en modo local y activar sincronizacion despues." ]
                    , button [ class "primary", type_ "button", onClick SignInWithGoogle ] [ text "Ingresar con Google" ]
                    ]


wizardAccountList : Model -> Html Msg
wizardAccountList model =
    case Model.activeAccounts model of
        [] ->
            p [ class "empty empty--compact" ] [ text "Todavia no hay cuentas." ]

        accounts ->
            Html.ul [ class "wizard-list" ]
                (List.map (\account -> Html.li [] [ text account.name ]) accounts)


wizardCollaboratorList : Model -> Html Msg
wizardCollaboratorList model =
    case currentLedger model of
        Nothing ->
            p [ class "empty empty--compact" ] [ text "Todavia no hay colaboradores invitados." ]

        Just ledger ->
            let
                collaborators =
                    List.filter (\member -> member.uid /= ledger.ownerUid) ledger.members

                collaboratorItems =
                    List.map (\member -> member.displayName ++ " <" ++ member.email ++ ">") collaborators

                inviteItems =
                    List.map (\email -> email ++ " (invitado)") ledger.invitedEmails

                items =
                    collaboratorItems ++ inviteItems
            in
            if List.isEmpty items then
                p [ class "empty empty--compact" ] [ text "Todavia no hay colaboradores invitados." ]

            else
                Html.ul [ class "wizard-list" ]
                    (List.map (\item -> Html.li [] [ text item ]) items)


currentLedger : Model -> Maybe Ledger.LedgerSummary
currentLedger model =
    model.ledgers
        |> List.filter (\ledger -> ledger.id == model.currentLedgerId)
        |> List.head


wizardStepLabel : WizardStep -> String
wizardStepLabel step =
    case step of
        WelcomeStep ->
            "1 de 3"

        AccountsStep ->
            "2 de 3"

        CollaboratorsStep ->
            "3 de 3"


advanceWizardFrom : WizardStep -> Model -> Model
advanceWizardFrom step model =
    case step of
        WelcomeStep ->
            { model | wizardState = WizardOpen (firstSetupStep model) }

        AccountsStep ->
            if List.isEmpty (Model.activeAccounts model) then
                { model | accountError = "Agrega al menos una cuenta para continuar." }

            else
                { model | wizardState = WizardOpen CollaboratorsStep, accountError = "" }

        CollaboratorsStep ->
            { model | wizardState = WizardCompleted, wizardCompletionVisible = True }


firstSetupStep : Model -> WizardStep
firstSetupStep model =
    if List.isEmpty (Model.activeAccounts model) then
        AccountsStep

    else
        CollaboratorsStep


previousWizardStep : Model -> WizardStep -> WizardStep
previousWizardStep model step =
    case step of
        WelcomeStep ->
            WelcomeStep

        AccountsStep ->
            WelcomeStep

        CollaboratorsStep ->
            if List.isEmpty (Model.activeAccounts model) then
                AccountsStep

            else
                WelcomeStep


wizardAfterAuth : Model -> WizardState
wizardAfterAuth model =
    case model.wizardState of
        WizardOpen WelcomeStep ->
            WizardOpen (firstSetupStep model)

        _ ->
            model.wizardState


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
                    , wizardState = wizardAfterAuth model
                  }
                , prepareLocalMigration ()
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
                    , wizardState = wizardAfterAuth model
                  }
                , loadLedgerData (Ledger.encodeLedgerRequest ledgerId)
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
        |> adjustWizardAfterLedgerLoad model.ledgerLoadState
        |> Model.ensureSelectedAccount


adjustWizardAfterLedgerLoad : LoadState -> Model -> Model
adjustWizardAfterLedgerLoad previousLoadState model =
    case model.wizardState of
        WizardOpen AccountsStep ->
            if previousLoadState == Loading && not (List.isEmpty (Model.activeAccounts model)) then
                { model | wizardState = WizardOpen CollaboratorsStep }

            else
                model

        _ ->
            model


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
