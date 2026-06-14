port module Main exposing (main)

import Accounting exposing (FilterWindow(..), SortDirection(..), SortField(..))
import Api.Dolar as Dolar exposing (ExchangeRateStatus(..), OfficialDollar)
import Auth exposing (AuthState(..))
import Browser
import Export
import Html exposing (Html, div, h1, header, main_, p, section, span, strong, text)
import Html.Attributes exposing (class)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Ledger exposing (LoadState(..))
import Model exposing (Model)
import Task
import Time
import Update.Accounts as Accounts
import Update.Expenses as Expenses
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
    | SelectFilter FilterWindow
    | UpdateCustomStart String
    | UpdateCustomEnd String
    | SelectDateDisplay DateDisplay
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


port exportTable : Encode.Value -> Cmd msg


port signInWithGoogle : () -> Cmd msg


port signOutUser : () -> Cmd msg


port authStateChanged : (Decode.Value -> msg) -> Sub msg


port loadLedgerData : Encode.Value -> Cmd msg


port saveExpense : Encode.Value -> Cmd msg


port generateExpenseId : () -> Cmd msg


port expenseIdGenerated : (Decode.Value -> msg) -> Sub msg


port saveAccount : Encode.Value -> Cmd msg


port deleteAccount : Encode.Value -> Cmd msg


port inviteLedgerGuest : Encode.Value -> Cmd msg


port removeLedgerGuest : Encode.Value -> Cmd msg


port updateLedgerName : Encode.Value -> Cmd msg


port saveLastAccountSelection : Encode.Value -> Cmd msg


port ledgerLoaded : (Decode.Value -> msg) -> Sub msg


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
    case Ledger.decodeLedger flags of
        Ok ledger ->
            applyLedgerData ledger Model.initial

        Err _ ->
            Model.initial


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
            ( { model | form = Accounting.setAmount amount model.form }, Cmd.none )

        UpdateAccount accountId ->
            ( { model | form = Accounting.setAccount accountId model.form }
            , saveLastAccount model.currentLedgerId accountId
            )

        UpdateCurrency currency ->
            ( { model | form = Accounting.setCurrency (Accounting.currencyFromString currency) model.form }, Cmd.none )

        UpdateDate date ->
            ( { model | form = Accounting.setDate date model.form }, Cmd.none )

        SelectFilter filterWindow ->
            ( { model | filterWindow = filterWindow }, Cmd.none )

        UpdateCustomStart date ->
            ( { model | customStart = date, filterWindow = Custom }, Cmd.none )

        UpdateCustomEnd date ->
            ( { model | customEnd = date, filterWindow = Custom }, Cmd.none )

        SelectDateDisplay dateDisplay ->
            ( { model | dateDisplay = dateDisplay }, Cmd.none )

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
                    in
                    case Accounting.buildExpense readyModel.exchangeRate expenseId (Model.activeAccounts readyModel) readyModel.form of
                        Ok expense ->
                            let
                                ( updatedModel, payload ) =
                                    Expenses.add expense readyModel
                            in
                            ( updatedModel
                            , Cmd.batch
                                [ payloadCmd saveExpense payload
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
                    , AuthStatus.view
                        { authState = model.authState
                        , ledgerLoadState = model.ledgerLoadState
                        , onSignIn = SignInWithGoogle
                        , onSignOut = SignOut
                        }
                    ]
                ]
            ]
        , main_ []
            [ div [ class "layout" ]
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
                    , onCurrency = UpdateCurrency
                    , onDate = UpdateDate
                    , onSubmit = AddExpense
                    }
                , div [ class "content-stack" ]
                    [ ExpenseTable.view
                        { expenses = rows
                        , accounts = Model.activeAccounts model
                        , filterWindow = model.filterWindow
                        , dateDisplay = model.dateDisplay
                        , customStart = model.customStart
                        , customEnd = model.customEnd
                        , sortField = model.sortField
                        , sortDirection = model.sortDirection
                        , onSelectFilter = SelectFilter
                        , onCustomStart = UpdateCustomStart
                        , onCustomEnd = UpdateCustomEnd
                        , onSelectDateDisplay = SelectDateDisplay
                        , onSelectSort = SelectSort
                        , onExportCsv = ExportCsv
                        , onExportXlsx = ExportXlsx
                        }
                    , adminArea model
                    ]
                ]
            ]
        ]


adminArea : Model -> Html Msg
adminArea model =
    section [ class "panel admin-panel" ]
        [ Html.details [ class "admin-disclosure" ]
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
        ]


handleAuthStateChanged : AuthState -> Model -> ( Model, Cmd Msg )
handleAuthStateChanged authState model =
    case authState of
        SignedIn user ->
            let
                ledgerId =
                    if model.currentLedgerId == "" then
                        user.uid

                    else
                        model.currentLedgerId
            in
            ( { model
                | authState = authState
                , ledgerLoadState = Loading
                , currentLedgerId = ledgerId
                , inviteEmail = ""
                , error = ""
                , accountError = ""
                , ledgerError = ""
              }
            , loadLedgerData (Ledger.encodeLedgerRequest ledgerId)
            )

        SignedOut ->
            ( { model
                | authState = authState
                , ledgerLoadState = NotLoaded
                , expenses = Model.sampleExpensesForModel model
                , accounts = Model.defaultAccounts
                , ledgers = []
                , currentLedgerId = ""
                , ledgerName = ""
                , inviteEmail = ""
                , error = ""
                , accountError = ""
                , ledgerError = ""
              }
                |> Model.ensureSelectedAccount
            , Cmd.none
            )

        _ ->
            ( { model | authState = authState }, Cmd.none )


handleLedgerLoaded : Decode.Value -> Model -> ( Model, Cmd Msg )
handleLedgerLoaded value model =
    case Ledger.decodeLedger value of
        Ok ledger ->
            ( applyLedgerData ledger model, Cmd.none )

        Err error ->
            ( { model | ledgerLoadState = LoadError error }, Cmd.none )


applyLedgerData : Ledger.LedgerData -> Model -> Model
applyLedgerData ledger model =
    let
        accounts =
            Model.activeAccountsFromList ledger.accounts

        form =
            formWithLoadedAccount ledger.lastAccountId accounts model.form
    in
    { model
        | expenses = Model.activeExpenses ledger.expenses
        , accounts = accounts
        , ledgers = ledger.ledgers
        , currentLedgerId = ledger.currentLedgerId
        , ledgerName = Model.ledgerNameFor ledger.currentLedgerId ledger.ledgers
        , form = form
        , ledgerLoadState = Loaded
        , error = ""
        , accountError = ""
        , ledgerError = ""
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
