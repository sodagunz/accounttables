module Model exposing
    ( MigrationState(..)
    , Model
    , StorageMode(..)
    , TutorialState(..)
    , TutorialStep(..)
    , activeAccounts
    , activeAccountsFromList
    , activeMovements
    , ensureSelectedAccount
    , initial
    , ledgerNameFor
    , selectedLedgerId
    , visibleMovements
    )

import Accounting exposing (Account, Currency(..), FilterWindow(..), Form, Movement, SortDirection(..), SortField(..))
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
    , exchangeRateStatus : ExchangeRateStatus
    , zone : Time.Zone
    , authState : AuthState
    , ledgerLoadState : LoadState
    , hiddenAccountIds : List String
    , migrationState : MigrationState
    , tutorialState : TutorialState
    , tutorialCompletionVisible : Bool
    , tutorialMovementId : Maybe String
    }


type StorageMode
    = LocalOnly
    | CloudSynced


type MigrationState
    = NoMigration
    | PreparingMigration
    | ChoosingMigration (List Ledger.LedgerSummary) String
    | UploadingMigration String


type TutorialStep
    = SignInStep
    | AccountsStep
    | CollaboratorsStep
    | FirstMovementStep
    | DeleteMovementStep


type TutorialState
    = TutorialOpen TutorialStep
    | TutorialDismissed
    | TutorialCompleted


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
    , migrationState = NoMigration
    , tutorialState = TutorialOpen SignInStep
    , tutorialCompletionVisible = False
    , tutorialMovementId = Nothing
    }


visibleMovements : Model -> List Movement
visibleMovements model =
    Accounting.filteredMovements { model | expenses = activeMovements model.expenses }
        |> List.filter (\e -> not (List.member e.accountId model.hiddenAccountIds))
        |> Accounting.sortMovements model.sortField model.sortDirection


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
