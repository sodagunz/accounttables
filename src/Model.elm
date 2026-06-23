module Model exposing
    ( ColorScheme(..)
    , MigrationState(..)
    , Model
    , StorageMode(..)
    , ViewMode(..)
    , activeAccounts
    , activeAccountsFromList
    , activeMovements
    , colorSchemeFromString
    , colorSchemeToString
    , ensureSelectedAccount
    , initial
    , ledgerNameFor
    , selectedLedgerId
    , visibleCashflowMovements
    , visibleInvoiceMovements
    , visibleInvoiceRelatedCashflows
    )

import Accounting exposing (Account, Currency(..), FilterWindow(..), Form, Movement, SortDirection(..), SortField(..), isCashflowMovement, isInvoiceMovement, isInvoiceRelatedCashflow)
import Api.Dolar exposing (ExchangeRateStatus(..))
import Auth exposing (AuthState(..))
import Events exposing (Event)
import Ledger exposing (LoadState(..))
import Time
import Util.Date exposing (DateDisplay(..))


type alias Model =
    { form : Form
    , storageMode : StorageMode
    , events : List Event
    , expenses : List Movement
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
    , exchangeRateDate : String
    , exchangeRateStatus : ExchangeRateStatus
    , zone : Time.Zone
    , authState : AuthState
    , ledgerLoadState : LoadState
    , hiddenAccountIds : List String
    , showInputAmountColumn : Bool
    , showExchangeRateColumn : Bool
    , migrationState : MigrationState
    , viewMode : ViewMode
    , colorScheme : ColorScheme
    }


type StorageMode
    = LocalOnly
    | CloudSynced


type MigrationState
    = NoMigration
    | PreparingMigration
    | ChoosingMigration (List Ledger.LedgerSummary) String
    | UploadingMigration String


type ViewMode
    = CashflowView
    | InvoiceView


type ColorScheme
    = LightScheme
    | DarkScheme


colorSchemeFromString : String -> ColorScheme
colorSchemeFromString value =
    case value of
        "dark" ->
            DarkScheme

        _ ->
            LightScheme


colorSchemeToString : ColorScheme -> String
colorSchemeToString colorScheme =
    case colorScheme of
        LightScheme ->
            "light"

        DarkScheme ->
            "dark"


initial : Model
initial =
    { form = Accounting.emptyForm
    , storageMode = LocalOnly
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
    , filterWindow = AllTime
    , dateDisplay = NumericDate
    , displayCurrency = ARS
    , sortField = SortByDate
    , sortDirection = Descending
    , exchangeRate = Accounting.fallbackExchangeRate
    , exchangeRateDate = ""
    , exchangeRateStatus = LoadingRate
    , zone = Time.utc
    , authState = AuthLoading
    , ledgerLoadState = NotLoaded
    , hiddenAccountIds = []
    , showInputAmountColumn = False
    , showExchangeRateColumn = False
    , migrationState = NoMigration
    , viewMode = CashflowView
    , colorScheme = LightScheme
    }


visibleMovements : Model -> List Movement
visibleMovements model =
    Accounting.filteredMovements { model | expenses = activeMovements model.expenses }
        |> List.filter (\e -> not (List.member e.accountId model.hiddenAccountIds))
        |> Accounting.sortMovements model.sortField model.sortDirection


visibleCashflowMovements : Model -> List Movement
visibleCashflowMovements model =
    visibleMovements model
        |> List.filter isCashflowMovement


visibleInvoiceMovements : Model -> List Movement
visibleInvoiceMovements model =
    visibleMovements model
        |> List.filter isInvoiceMovement


visibleInvoiceRelatedCashflows : Model -> List Movement
visibleInvoiceRelatedCashflows model =
    visibleMovements model
        |> List.filter isInvoiceRelatedCashflow


defaultAccounts : List Account
defaultAccounts =
    []


activeAccounts : Model -> List Account
activeAccounts model =
    activeAccountsFromList model.accounts


activeAccountsFromList : List Account -> List Account
activeAccountsFromList accounts =
    List.filter (\account -> account.deletedAt == Nothing) accounts


activeMovements : List Movement -> List Movement
activeMovements movements =
    List.filter (\movement -> movement.deletedAt == Nothing) movements


ensureSelectedAccount : Model -> Model
ensureSelectedAccount model =
    if List.any (\account -> account.id == model.form.accountId) (activeAccounts model) then
        model

    else
        case activeAccounts model of
            account :: _ ->
                { model | form = Accounting.setAccount account.id model.form }

            [] ->
                model


selectedLedgerId : Model -> String
selectedLedgerId model =
    if model.currentLedgerId == "" then
        Ledger.localLedgerId

    else
        model.currentLedgerId


ledgerNameFor : String -> List Ledger.LedgerSummary -> String
ledgerNameFor ledgerId ledgers =
    ledgers
        |> List.filter (\ledger -> ledger.id == ledgerId)
        |> List.head
        |> Maybe.map .name
        |> Maybe.withDefault ""
