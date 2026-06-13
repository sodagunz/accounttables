port module Main exposing (main)

import Accounting exposing (Account, Currency(..), Expense, FilterWindow(..), Form, SortDirection(..), SortField(..))
import Api.Dolar as Dolar exposing (ExchangeRateStatus(..), OfficialDollar)
import Auth exposing (AuthState(..))
import Browser
import Export
import Html exposing (Html, div, h1, header, main_, p, text)
import Html.Attributes exposing (class)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import String
import Task
import Time
import Util.Date exposing (DateDisplay(..), dateToIso)
import View.AuthStatus as AuthStatus
import View.ExpenseForm as ExpenseForm
import View.ExpenseTable as ExpenseTable
import View.WorkspaceAccess as WorkspaceAccess
import View.WorkspaceAccounts as WorkspaceAccounts
import Workspace exposing (LoadState(..))


type alias Model =
    { form : Form
    , expenses : List Expense
    , accounts : List Account
    , workspaces : List Workspace.WorkspaceSummary
    , currentWorkspaceId : String
    , workspaceName : String
    , inviteEmail : String
    , workspaceError : String
    , newAccountName : String
    , accountError : String
    , error : String
    , today : String
    , filterWindow : FilterWindow
    , customStart : String
    , customEnd : String
    , dateDisplay : DateDisplay
    , sortField : SortField
    , sortDirection : SortDirection
    , exchangeRate : Float
    , exchangeRateStatus : ExchangeRateStatus
    , zone : Time.Zone
    , authState : AuthState
    , workspaceLoadState : LoadState
    }


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
    | WorkspaceLoaded Decode.Value
    | GotExchangeRate (Result Http.Error OfficialDollar)
    | AddExpense
    | ExpenseIdGenerated Decode.Value
    | UpdateNewAccountName String
    | AddAccount
    | DeleteAccount String
    | SelectWorkspace String
    | UpdateWorkspaceName String
    | SaveWorkspaceName
    | UpdateInviteEmail String
    | InviteGuest
    | RemoveGuest String


port exportTable : Encode.Value -> Cmd msg


port signInWithGoogle : () -> Cmd msg


port signOutUser : () -> Cmd msg


port authStateChanged : (Decode.Value -> msg) -> Sub msg


port loadWorkspaceData : Encode.Value -> Cmd msg


port saveExpense : Encode.Value -> Cmd msg


port generateExpenseId : () -> Cmd msg


port expenseIdGenerated : (Decode.Value -> msg) -> Sub msg


port saveAccount : Encode.Value -> Cmd msg


port deleteAccount : Encode.Value -> Cmd msg


port inviteWorkspaceGuest : Encode.Value -> Cmd msg


port removeWorkspaceGuest : Encode.Value -> Cmd msg


port updateWorkspaceName : Encode.Value -> Cmd msg


port workspaceLoaded : (Decode.Value -> msg) -> Sub msg


main : Program () Model Msg
main =
    Browser.element
        { init = \_ -> init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


init : ( Model, Cmd Msg )
init =
    ( { form = Accounting.emptyForm
      , expenses = []
      , accounts = defaultAccounts
      , workspaces = []
      , currentWorkspaceId = ""
      , workspaceName = ""
      , inviteEmail = ""
      , workspaceError = ""
      , newAccountName = ""
      , accountError = ""
      , error = ""
      , today = ""
      , filterWindow = AllTime
      , customStart = ""
      , customEnd = ""
      , dateDisplay = NumericDate
      , sortField = SortByDate
      , sortDirection = Descending
      , exchangeRate = Accounting.fallbackExchangeRate
      , exchangeRateStatus = LoadingRate
      , zone = Time.utc
      , authState = AuthLoading
      , workspaceLoadState = NotLoaded
      }
    , Cmd.batch
        [ Task.perform identity (Task.map2 GotToday Time.here Time.now)
        , Dolar.fetchOfficialDollar GotExchangeRate
        ]
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
                , expenses = Accounting.sampleExpenses model.exchangeRate today model.accounts
                , zone = zone
              }
                |> ensureSelectedAccount
            , Cmd.none
            )

        UpdateDescription description ->
            ( { model | form = Accounting.setDescription description model.form }, Cmd.none )

        UpdateAmount amount ->
            ( { model | form = Accounting.setAmount amount model.form }, Cmd.none )

        UpdateAccount accountId ->
            ( { model | form = Accounting.setAccount accountId model.form }, Cmd.none )

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

        WorkspaceLoaded value ->
            handleWorkspaceLoaded value model

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
                    case Accounting.buildExpense model.exchangeRate expenseId (activeAccounts model) model.form of
                        Ok expense ->
                            addExpense expense model

                        Err error ->
                            ( { model | error = error }, Cmd.none )

                Err error ->
                    ( { model | error = Decode.errorToString error }, Cmd.none )

        UpdateNewAccountName name ->
            ( { model | newAccountName = name }, Cmd.none )

        AddAccount ->
            addAccount model

        DeleteAccount accountId ->
            deleteAccountById accountId model

        SelectWorkspace workspaceId ->
            ( { model
                | currentWorkspaceId = workspaceId
                , workspaceName = workspaceNameFor workspaceId model.workspaces
                , workspaceLoadState = Loading
                , expenses = []
                , accounts = []
                , error = ""
                , accountError = ""
                , workspaceError = ""
              }
            , loadWorkspaceData (Workspace.encodeWorkspaceRequest workspaceId)
            )

        UpdateWorkspaceName name ->
            ( { model | workspaceName = name }, Cmd.none )

        SaveWorkspaceName ->
            saveWorkspaceName model

        UpdateInviteEmail email ->
            ( { model | inviteEmail = email }, Cmd.none )

        InviteGuest ->
            inviteGuest model

        RemoveGuest uid ->
            removeGuest uid model


inviteGuest : Model -> ( Model, Cmd Msg )
inviteGuest model =
    let
        email =
            String.toLower (String.trim model.inviteEmail)
    in
    if email == "" then
        ( { model | workspaceError = "Ingresa un email." }, Cmd.none )

    else if selectedWorkspaceId model == "" then
        ( { model | workspaceError = "Selecciona un workspace." }, Cmd.none )

    else
        ( { model | inviteEmail = "", workspaceError = "" }
        , inviteWorkspaceGuest (Workspace.encodeGuestInvite (selectedWorkspaceId model) email)
        )


removeGuest : String -> Model -> ( Model, Cmd Msg )
removeGuest uid model =
    if selectedWorkspaceId model == "" then
        ( { model | workspaceError = "Selecciona un workspace." }, Cmd.none )

    else
        ( { model | workspaceError = "" }
        , removeWorkspaceGuest (Workspace.encodeGuestRemove (selectedWorkspaceId model) uid)
        )


saveWorkspaceName : Model -> ( Model, Cmd Msg )
saveWorkspaceName model =
    let
        name =
            String.trim model.workspaceName
    in
    if name == "" then
        ( { model | workspaceError = "Ingresa un nombre para el workspace." }, Cmd.none )

    else if selectedWorkspaceId model == "" then
        ( { model | workspaceError = "Selecciona un workspace." }, Cmd.none )

    else
        ( { model | workspaceName = name, workspaceError = "" }
        , updateWorkspaceName (Workspace.encodeWorkspaceName (selectedWorkspaceId model) name)
        )


addAccount : Model -> ( Model, Cmd Msg )
addAccount model =
    let
        name =
            String.trim model.newAccountName
    in
    if name == "" then
        ( { model | accountError = "Ingresa un nombre." }, Cmd.none )

    else
        case model.authState of
            SignedIn _ ->
                if selectedWorkspaceId model == "" then
                    ( { model | accountError = "Selecciona un workspace." }, Cmd.none )

                else
                    ( { model | newAccountName = "", accountError = "" }
                    , saveAccount (Workspace.encodeAccountCreate (selectedWorkspaceId model) name)
                    )

            _ ->
                ( { model | accountError = "Ingresa con Google para guardar cajas en el workspace." }, Cmd.none )


deleteAccountById : String -> Model -> ( Model, Cmd Msg )
deleteAccountById accountId model =
    case model.authState of
        SignedIn _ ->
            if selectedWorkspaceId model == "" then
                ( { model | accountError = "Selecciona un workspace." }, Cmd.none )

            else
                ( { model | accountError = "" }
                , deleteAccount (Workspace.encodeAccountDelete (selectedWorkspaceId model) accountId)
                )

        _ ->
            ( { model | accountError = "Ingresa con Google para modificar cajas del workspace." }, Cmd.none )


view : Model -> Html Msg
view model =
    let
        rows =
            visibleExpenses model
    in
    div [ class "app" ]
        [ header [ class "topbar" ]
            [ div [ class "topbar__inner" ]
                [ div [ class "topbar__content" ]
                    [ div []
                        [ h1 [] [ text "ContabilizAR" ]
                        , p [ class "subtitle" ] [ text "Un registro simple de gastos por workspace, con conversión AR$/U$D y una tabla filtrable." ]
                        ]
                    , AuthStatus.view
                        { authState = model.authState
                        , workspaceLoadState = model.workspaceLoadState
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
                    , accounts = activeAccounts model
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
                    [ WorkspaceAccess.view
                        { authState = model.authState
                        , workspaces = model.workspaces
                        , currentWorkspaceId = model.currentWorkspaceId
                        , workspaceName = model.workspaceName
                        , inviteEmail = model.inviteEmail
                        , error = model.workspaceError
                        , onSelectWorkspace = SelectWorkspace
                        , onWorkspaceName = UpdateWorkspaceName
                        , onSaveWorkspaceName = SaveWorkspaceName
                        , onInviteEmail = UpdateInviteEmail
                        , onInvite = InviteGuest
                        , onRemoveGuest = RemoveGuest
                        }
                    , WorkspaceAccounts.view
                        { accounts = activeAccounts model
                        , newAccountName = model.newAccountName
                        , error = model.accountError
                        , onName = UpdateNewAccountName
                        , onAdd = AddAccount
                        , onDelete = DeleteAccount
                        }
                    , ExpenseTable.view
                        { expenses = rows
                        , accounts = activeAccounts model
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
                    ]
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
    exportTable (Export.tablePayload format model.dateDisplay model.today (activeAccounts model) (visibleExpenses model))


visibleExpenses : Model -> List Expense
visibleExpenses model =
    Accounting.filteredExpenses { model | expenses = activeExpenses model.expenses }
        |> Accounting.sortExpenses model.sortField model.sortDirection


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ authStateChanged AuthStateChanged
        , workspaceLoaded WorkspaceLoaded
        , expenseIdGenerated ExpenseIdGenerated
        ]


handleAuthStateChanged : AuthState -> Model -> ( Model, Cmd Msg )
handleAuthStateChanged authState model =
    case authState of
        SignedIn user ->
            ( { model
                | authState = authState
                , workspaceLoadState = Loading
                , expenses = []
                , accounts = []
                , workspaces = []
                , currentWorkspaceId = user.uid
                , workspaceName = ""
                , inviteEmail = ""
                , error = ""
                , accountError = ""
                , workspaceError = ""
              }
            , loadWorkspaceData (Workspace.encodeWorkspaceRequest user.uid)
            )

        SignedOut ->
            ( { model
                | authState = authState
                , workspaceLoadState = NotLoaded
                , expenses = sampleExpensesForModel model
                , accounts = defaultAccounts
                , workspaces = []
                , currentWorkspaceId = ""
                , workspaceName = ""
                , inviteEmail = ""
                , error = ""
                , accountError = ""
                , workspaceError = ""
              }
                |> ensureSelectedAccount
            , Cmd.none
            )

        _ ->
            ( { model | authState = authState }, Cmd.none )


handleWorkspaceLoaded : Decode.Value -> Model -> ( Model, Cmd Msg )
handleWorkspaceLoaded value model =
    case Workspace.decodeWorkspace value of
        Ok workspace ->
            ( { model
                | expenses = activeExpenses workspace.expenses
                , accounts = activeAccountsFromList workspace.accounts
                , workspaces = workspace.workspaces
                , currentWorkspaceId = workspace.currentWorkspaceId
                , workspaceName = workspaceNameFor workspace.currentWorkspaceId workspace.workspaces
                , workspaceLoadState = Loaded
                , error = ""
                , accountError = ""
                , workspaceError = ""
              }
                |> ensureSelectedAccount
            , Cmd.none
            )

        Err error ->
            ( { model | workspaceLoadState = LoadError error }, Cmd.none )


addExpense : Expense -> Model -> ( Model, Cmd Msg )
addExpense expense model =
    let
        updatedModel =
            { model
                | expenses = expense :: model.expenses
                , form =
                    { description = ""
                    , amount = ""
                    , accountId = model.form.accountId
                    , currency = ARS
                    , date = model.form.date
                    }
                , error = ""
            }
    in
    case model.authState of
        SignedIn _ ->
            if selectedWorkspaceId model == "" then
                ( { updatedModel | error = "Selecciona un workspace." }, Cmd.none )

            else
                ( updatedModel
                , saveExpense (Workspace.encodeExpense (selectedWorkspaceId model) expense)
                )

        _ ->
            ( updatedModel, Cmd.none )


sampleExpensesForModel : Model -> List Expense
sampleExpensesForModel model =
    if model.today == "" then
        []

    else
        Accounting.sampleExpenses model.exchangeRate model.today model.accounts


defaultAccounts : List Account
defaultAccounts =
    []


activeAccounts : Model -> List Account
activeAccounts model =
    activeAccountsFromList model.accounts


activeAccountsFromList : List Account -> List Account
activeAccountsFromList accounts =
    List.filter (\account -> account.deletedAt == Nothing) accounts


activeExpenses : List Expense -> List Expense
activeExpenses expenses =
    List.filter (\expense -> expense.deletedAt == Nothing) expenses


ensureSelectedAccount : Model -> Model
ensureSelectedAccount model =
    if List.any (\account -> account.id == model.form.accountId) (activeAccounts model) then
        model

    else
        case activeAccounts model of
            account :: _ ->
                { model | form = Accounting.setAccount account.id model.form }

            [] ->
                { model | form = Accounting.setAccount "" model.form }


selectedWorkspaceId : Model -> String
selectedWorkspaceId model =
    model.currentWorkspaceId


workspaceNameFor : String -> List Workspace.WorkspaceSummary -> String
workspaceNameFor workspaceId workspaces =
    workspaces
        |> List.filter (\workspace -> workspace.id == workspaceId)
        |> List.head
        |> Maybe.map .name
        |> Maybe.withDefault ""
