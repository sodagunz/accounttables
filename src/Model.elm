module Model exposing
    ( Model
    , activeAccounts
    , activeAccountsFromList
    , activeExpenses
    , defaultAccounts
    , ensureSelectedAccount
    , initial
    , ledgerNameFor
    , sampleExpensesForModel
    , selectedLedgerId
    , visibleExpenses
    )

import Accounting exposing (Account, Currency(..), Expense, FilterWindow(..), Form, SortDirection(..), SortField(..))
import Api.Dolar exposing (ExchangeRateStatus(..))
import Auth exposing (AuthState(..))
import Events exposing (Event)
import Ledger exposing (LoadState(..))
import Time
import Util.Date exposing (DateDisplay(..))


type alias Model =
    { form : Form
    , events : List Event
    , expenses : List Expense
    , accounts : List Account
    , ledgers : List Ledger.LedgerSummary
    , currentLedgerId : String
    , ledgerName : String
    , inviteEmail : String
    , ledgerError : String
    , newAccountName : String
    , accountError : String
    , error : String
    , today : String
    , filterWindow : FilterWindow
    , dateDisplay : DateDisplay
    , displayCurrency : Currency
    , sortField : SortField
    , sortDirection : SortDirection
    , exchangeRate : Float
    , exchangeRateStatus : ExchangeRateStatus
    , zone : Time.Zone
    , authState : AuthState
    , ledgerLoadState : LoadState
    , hiddenAccountIds : List String
    }


initial : Model
initial =
    { form = Accounting.emptyForm
    , events = []
    , expenses = []
    , accounts = defaultAccounts
    , ledgers = []
    , currentLedgerId = ""
    , ledgerName = ""
    , inviteEmail = ""
    , ledgerError = ""
    , newAccountName = ""
    , accountError = ""
    , error = ""
    , today = ""
    , filterWindow = ThisMonth
    , dateDisplay = NumericDate
    , displayCurrency = ARS
    , sortField = SortByDate
    , sortDirection = Descending
    , exchangeRate = Accounting.fallbackExchangeRate
    , exchangeRateStatus = LoadingRate
    , zone = Time.utc
    , authState = AuthLoading
    , ledgerLoadState = NotLoaded
    , hiddenAccountIds = []
    }


visibleExpenses : Model -> List Expense
visibleExpenses model =
    Accounting.filteredExpenses { model | expenses = activeExpenses model.expenses }
        |> List.filter (\e -> not (List.member e.accountId model.hiddenAccountIds))
        |> Accounting.sortExpenses model.sortField model.sortDirection


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


selectedLedgerId : Model -> String
selectedLedgerId model =
    model.currentLedgerId


ledgerNameFor : String -> List Ledger.LedgerSummary -> String
ledgerNameFor ledgerId ledgers =
    ledgers
        |> List.filter (\ledger -> ledger.id == ledgerId)
        |> List.head
        |> Maybe.map .name
        |> Maybe.withDefault ""
