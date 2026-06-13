port module Main exposing (main)

import Accounting exposing (Currency(..), Expense, FilterWindow(..), Form, SortDirection(..), SortField(..), WorkspaceUser)
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
import View.WorkspaceUsers as WorkspaceUsers
import Workspace exposing (LoadState(..))


type alias Model =
    { form : Form
    , expenses : List Expense
    , users : List WorkspaceUser
    , workspaces : List Workspace.WorkspaceSummary
    , currentWorkspaceId : String
    , workspaceName : String
    , inviteEmail : String
    , workspaceError : String
    , newUserName : String
    , userError : String
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
    | UpdatePerson String
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
    | UpdateNewUserName String
    | AddWorkspaceUser
    | DeleteWorkspaceUser String
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


port saveWorkspaceUser : Encode.Value -> Cmd msg


port deleteWorkspaceUser : Encode.Value -> Cmd msg


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
      , users = defaultUsers
      , workspaces = []
      , currentWorkspaceId = ""
      , workspaceName = ""
      , inviteEmail = ""
      , workspaceError = ""
      , newUserName = ""
      , userError = ""
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
                , expenses = Accounting.sampleExpenses model.exchangeRate today model.users
                , zone = zone
              }
                |> ensureSelectedUser
            , Cmd.none
            )

        UpdateDescription description ->
            ( { model | form = Accounting.setDescription description model.form }, Cmd.none )

        UpdateAmount amount ->
            ( { model | form = Accounting.setAmount amount model.form }, Cmd.none )

        UpdatePerson person ->
            ( { model | form = Accounting.setUser person model.form }, Cmd.none )

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
                    case Accounting.buildExpense model.exchangeRate expenseId (activeUsers model) model.form of
                        Ok expense ->
                            addExpense expense model

                        Err error ->
                            ( { model | error = error }, Cmd.none )

                Err error ->
                    ( { model | error = Decode.errorToString error }, Cmd.none )

        UpdateNewUserName name ->
            ( { model | newUserName = name }, Cmd.none )

        AddWorkspaceUser ->
            addWorkspaceUser model

        DeleteWorkspaceUser userId ->
            deleteWorkspaceUserById userId model

        SelectWorkspace workspaceId ->
            ( { model
                | currentWorkspaceId = workspaceId
                , workspaceName = workspaceNameFor workspaceId model.workspaces
                , workspaceLoadState = Loading
                , expenses = []
                , users = []
                , error = ""
                , userError = ""
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


addWorkspaceUser : Model -> ( Model, Cmd Msg )
addWorkspaceUser model =
    let
        name =
            String.trim model.newUserName
    in
    if name == "" then
        ( { model | userError = "Ingresa un nombre." }, Cmd.none )

    else
        case model.authState of
            SignedIn _ ->
                if selectedWorkspaceId model == "" then
                    ( { model | userError = "Selecciona un workspace." }, Cmd.none )

                else
                    ( { model | newUserName = "", userError = "" }
                    , saveWorkspaceUser (Workspace.encodeUserCreate (selectedWorkspaceId model) name)
                    )

            _ ->
                ( { model | userError = "Ingresa con Google para guardar personas en el workspace." }, Cmd.none )


deleteWorkspaceUserById : String -> Model -> ( Model, Cmd Msg )
deleteWorkspaceUserById userId model =
    case model.authState of
        SignedIn _ ->
            if selectedWorkspaceId model == "" then
                ( { model | userError = "Selecciona un workspace." }, Cmd.none )

            else
                ( { model | userError = "" }
                , deleteWorkspaceUser (Workspace.encodeUserDelete (selectedWorkspaceId model) userId)
                )

        _ ->
            ( { model | userError = "Ingresa con Google para modificar personas del workspace." }, Cmd.none )


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
                    , users = activeUsers model
                    , exchangeRate = model.exchangeRate
                    , exchangeRateStatus = model.exchangeRateStatus
                    , zone = model.zone
                    , error = model.error
                    , onDescription = UpdateDescription
                    , onAmount = UpdateAmount
                    , onPerson = UpdatePerson
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
                    , WorkspaceUsers.view
                        { users = activeUsers model
                        , newUserName = model.newUserName
                        , error = model.userError
                        , onName = UpdateNewUserName
                        , onAdd = AddWorkspaceUser
                        , onDelete = DeleteWorkspaceUser
                        }
                    , ExpenseTable.view
                        { expenses = rows
                        , users = activeUsers model
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

        SortByPerson ->
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
    exportTable (Export.tablePayload format model.dateDisplay model.today (activeUsers model) (visibleExpenses model))


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
                , users = []
                , workspaces = []
                , currentWorkspaceId = user.uid
                , workspaceName = ""
                , inviteEmail = ""
                , error = ""
                , userError = ""
                , workspaceError = ""
              }
            , loadWorkspaceData (Workspace.encodeWorkspaceRequest user.uid)
            )

        SignedOut ->
            ( { model
                | authState = authState
                , workspaceLoadState = NotLoaded
                , expenses = sampleExpensesForModel model
                , users = defaultUsers
                , workspaces = []
                , currentWorkspaceId = ""
                , workspaceName = ""
                , inviteEmail = ""
                , error = ""
                , userError = ""
                , workspaceError = ""
              }
                |> ensureSelectedUser
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
                , users = activeUsersFromList workspace.users
                , workspaces = workspace.workspaces
                , currentWorkspaceId = workspace.currentWorkspaceId
                , workspaceName = workspaceNameFor workspace.currentWorkspaceId workspace.workspaces
                , workspaceLoadState = Loaded
                , error = ""
                , userError = ""
                , workspaceError = ""
              }
                |> ensureSelectedUser
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
                    , userId = model.form.userId
                    , currency = ARS
                    , date = model.form.date
                    }
                , error = ""
            }
    in
    case model.authState of
        SignedIn user ->
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
        Accounting.sampleExpenses model.exchangeRate model.today model.users


defaultUsers : List WorkspaceUser
defaultUsers =
    []


activeUsers : Model -> List WorkspaceUser
activeUsers model =
    activeUsersFromList model.users


activeUsersFromList : List WorkspaceUser -> List WorkspaceUser
activeUsersFromList users =
    List.filter (\user -> user.deletedAt == Nothing) users


activeExpenses : List Expense -> List Expense
activeExpenses expenses =
    List.filter (\expense -> expense.deletedAt == Nothing) expenses


ensureSelectedUser : Model -> Model
ensureSelectedUser model =
    if List.any (\user -> user.id == model.form.userId) (activeUsers model) then
        model

    else
        case activeUsers model of
            user :: _ ->
                { model | form = Accounting.setUser user.id model.form }

            [] ->
                { model | form = Accounting.setUser "" model.form }


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
