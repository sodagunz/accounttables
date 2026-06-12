module Main exposing (main)

import Accounting exposing (Currency(..), Expense, FilterWindow(..), Form, SortDirection(..), SortField(..))
import Api.Dolar as Dolar exposing (ExchangeRateStatus(..), OfficialDollar)
import Browser
import Html exposing (Html, div, h1, header, main_, p, text)
import Html.Attributes exposing (class)
import Http
import Task
import Time
import Util.Date exposing (DateDisplay(..), dateToIso)
import View.ExpenseForm as ExpenseForm
import View.ExpenseTable as ExpenseTable


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
    | GotExchangeRate (Result Http.Error OfficialDollar)
    | AddExpense


main : Program () Model Msg
main =
    Browser.element
        { init = \_ -> init
        , update = update
        , subscriptions = \_ -> Sub.none
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
                    ( { model
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
                    , Cmd.none
                    )

                Err error ->
                    ( { model | error = error }, Cmd.none )


view : Model -> Html Msg
view model =
    let
        visibleExpenses =
            Accounting.filteredExpenses model
                |> Accounting.sortExpenses model.sortField model.sortDirection
    in
    div [ class "app" ]
        [ header [ class "topbar" ]
            [ div [ class "topbar__inner" ]
                [ h1 [] [ text "ContabilizAR" ]
                , p [ class "subtitle" ] [ text "Un registro simple de gastos para Alice y Bob, con conversión AR$/U$D y una tabla filtrable." ]
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
                        { expenses = visibleExpenses
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

        SortByAmount ->
            Descending
