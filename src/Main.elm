port module Main exposing (main)

import Accounting exposing (Currency(..), Expense, FilterWindow(..), Form, SortDirection(..), SortField(..))
import Api.Dolar as Dolar exposing (ExchangeRateStatus(..), OfficialDollar)
import Auth exposing (AuthState(..))
import Browser
import Export
import Html exposing (Html, div, h1, header, main_, p, text)
import Html.Attributes exposing (class)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Task
import Time
import Util.Date exposing (DateDisplay(..), dateToIso)
import View.AuthStatus as AuthStatus
import View.ExpenseForm as ExpenseForm
import View.ExpenseTable as ExpenseTable
import Workspace exposing (LoadState(..))


type alias Model =
    { form : Form
    , expenses : List Expense
    , nextId : Int
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


port exportTable : Encode.Value -> Cmd msg


port signInWithGoogle : () -> Cmd msg


port signOutUser : () -> Cmd msg


port authStateChanged : (Decode.Value -> msg) -> Sub msg


port loadWorkspaceData : Encode.Value -> Cmd msg


port saveExpense : Encode.Value -> Cmd msg


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
      , nextId = 1
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
                , expenses = Accounting.sampleExpenses model.exchangeRate today
                , nextId = 5
                , zone = zone
              }
            , Cmd.none
            )

        UpdateDescription description ->
            ( { model | form = Accounting.setDescription description model.form }, Cmd.none )

        UpdateAmount amount ->
            ( { model | form = Accounting.setAmount amount model.form }, Cmd.none )

        UpdatePerson person ->
            ( { model | form = Accounting.setPerson (Accounting.personFromString person) model.form }, Cmd.none )

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
            case Accounting.buildExpense model.exchangeRate model.nextId model.form of
                Ok expense ->
                    addExpense expense model

                Err error ->
                    ( { model | error = error }, Cmd.none )


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
                        , p [ class "subtitle" ] [ text "Un registro simple de gastos para Alice y Bob, con conversión AR$/U$D y una tabla filtrable." ]
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
                    [ ExpenseTable.view
                        { expenses = rows
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
    model
        |> visibleExpenses
        |> Export.tablePayload format model.dateDisplay model.today
        |> exportTable


visibleExpenses : Model -> List Expense
visibleExpenses model =
    Accounting.filteredExpenses model
        |> Accounting.sortExpenses model.sortField model.sortDirection


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ authStateChanged AuthStateChanged
        , workspaceLoaded WorkspaceLoaded
        ]


handleAuthStateChanged : AuthState -> Model -> ( Model, Cmd Msg )
handleAuthStateChanged authState model =
    case authState of
        SignedIn user ->
            let
                workspaceId =
                    Workspace.workspaceIdForUser user
            in
            ( { model
                | authState = authState
                , workspaceLoadState = Loading
                , expenses = []
                , nextId = 1
              }
            , loadWorkspaceData (Workspace.encodeWorkspaceRequest workspaceId)
            )

        SignedOut ->
            ( { model
                | authState = authState
                , workspaceLoadState = NotLoaded
                , expenses = sampleExpensesForModel model
                , nextId = 5
              }
            , Cmd.none
            )

        _ ->
            ( { model | authState = authState }, Cmd.none )


handleWorkspaceLoaded : Decode.Value -> Model -> ( Model, Cmd Msg )
handleWorkspaceLoaded value model =
    case Workspace.decodeExpenses value of
        Ok expenses ->
            ( { model
                | expenses = expenses
                , nextId = nextExpenseId expenses
                , workspaceLoadState = Loaded
              }
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
                , nextId = model.nextId + 1
                , form =
                    { description = ""
                    , amount = ""
                    , person = model.form.person
                    , currency = ARS
                    , date = model.form.date
                    }
                , error = ""
            }
    in
    case model.authState of
        SignedIn user ->
            ( updatedModel
            , saveExpense (Workspace.encodeExpense (Workspace.workspaceIdForUser user) expense)
            )

        _ ->
            ( updatedModel, Cmd.none )


nextExpenseId : List Expense -> Int
nextExpenseId expenses =
    expenses
        |> List.map .id
        |> List.maximum
        |> Maybe.map ((+) 1)
        |> Maybe.withDefault 1


sampleExpensesForModel : Model -> List Expense
sampleExpensesForModel model =
    if model.today == "" then
        []

    else
        Accounting.sampleExpenses model.exchangeRate model.today
