module Accounting exposing
    ( Account
    , Currency(..)
    , Expense
    , FilterWindow(..)
    , Form
    , MoneyTotal
    , SortDirection(..)
    , SortField(..)
    , addMoney
    , buildExpense
    , convert
    , currencyFromString
    , currencyToString
    , emptyForm
    , emptyMoney
    , expenseMatchesFilter
    , expensesFor
    , fallbackExchangeRate
    , filteredExpenses
    , sampleExpenses
    , setAccount
    , setAmount
    , setCurrency
    , setDate
    , setDescription
    , sortExpenses
    , summarizeMoney
    )

import String
import Util.Date as Date


fallbackExchangeRate : Float
fallbackExchangeRate =
    1450


type Currency
    = ARS
    | USD


type FilterWindow
    = AllTime
    | ThisYear
    | ThisMonth
    | ThisWeek
    | Today
    | Custom


type SortField
    = SortByDate
    | SortByAccount
    | SortByDescription
    | SortByExchangeRate
    | SortByPesos
    | SortByDollars


type SortDirection
    = Ascending
    | Descending


type alias Expense =
    { id : String
    , description : String
    , accountId : String
    , accountName : String
    , inputAmount : Float
    , inputCurrency : Currency
    , exchangeRate : Float
    , ars : Float
    , usd : Float
    , date : String
    , deletedAt : Maybe String
    }


type alias Account =
    { id : String
    , name : String
    , deletedAt : Maybe String
    }


type alias Form =
    { description : String
    , amount : String
    , accountId : String
    , currency : Currency
    , date : String
    }


type alias MoneyTotal =
    { ars : Float
    , usd : Float
    }


emptyForm : Form
emptyForm =
    { description = ""
    , amount = ""
    , accountId = ""
    , currency = ARS
    , date = ""
    }


setDescription : String -> Form -> Form
setDescription description form =
    { form | description = description }


setAmount : String -> Form -> Form
setAmount amount form =
    { form | amount = amount }


setAccount : String -> Form -> Form
setAccount accountId form =
    { form | accountId = accountId }


setCurrency : Currency -> Form -> Form
setCurrency currency form =
    { form | currency = currency }


setDate : String -> Form -> Form
setDate date form =
    { form | date = date }


buildExpense : Float -> String -> List Account -> Form -> Result String Expense
buildExpense exchangeRate id accounts form =
    let
        description =
            String.trim form.description

        selectedAccount =
            accounts
                |> List.filter (\account -> account.id == form.accountId && account.deletedAt == Nothing)
                |> List.head
    in
    case String.toFloat form.amount of
        Nothing ->
            Err "Ingresa un monto válido."

        Just amount ->
            if description == "" then
                Err "Ingresa una descripción."

            else if amount <= 0 then
                Err "El monto debe ser mayor que cero."

            else if Date.dateFromIso form.date == Nothing then
                Err "Ingresa una fecha válida."

            else
                case selectedAccount of
                    Nothing ->
                        Err "Selecciona una caja."

                    Just account ->
                        let
                            converted =
                                convert exchangeRate form.currency amount
                        in
                        Ok
                            { id = id
                            , description = description
                            , accountId = account.id
                            , accountName = account.name
                            , inputAmount = amount
                            , inputCurrency = form.currency
                            , exchangeRate = exchangeRate
                            , ars = converted.ars
                            , usd = converted.usd
                            , date = form.date
                            , deletedAt = Nothing
                            }


convert : Float -> Currency -> Float -> { ars : Float, usd : Float }
convert exchangeRate currency amount =
    case currency of
        ARS ->
            { ars = amount, usd = amount / exchangeRate }

        USD ->
            { ars = amount * exchangeRate, usd = amount }


emptyMoney : MoneyTotal
emptyMoney =
    { ars = 0, usd = 0 }


summarizeMoney : List Expense -> MoneyTotal
summarizeMoney expenses =
    List.foldl addMoney emptyMoney expenses


addMoney : Expense -> MoneyTotal -> MoneyTotal
addMoney expense total =
    { ars = total.ars + expense.ars
    , usd = total.usd + expense.usd
    }


expensesFor : Account -> List Expense -> List Expense
expensesFor account expenses =
    List.filter (\expense -> expense.accountId == account.id) expenses


sampleExpenses : Float -> String -> List Account -> List Expense
sampleExpenses exchangeRate today accounts =
    let
        yesterday =
            Date.addDays -1 today

        lastWeek =
            Date.addDays -7 today
    in
    case accounts of
        first :: second :: _ ->
            [ sampleExpense exchangeRate "018f0000-0000-7000-8000-000000000001" "Supermercado" first 28500 ARS today
            , sampleExpense exchangeRate "018f0000-0000-7000-8000-000000000002" "Nafta" second 42 USD today
            , sampleExpense exchangeRate "018f0000-0000-7000-8000-000000000003" "Almuerzo" first 12500 ARS yesterday
            , sampleExpense exchangeRate "018f0000-0000-7000-8000-000000000004" "Librería" second 18500 ARS lastWeek
            ]

        first :: [] ->
            [ sampleExpense exchangeRate "018f0000-0000-7000-8000-000000000001" "Supermercado" first 28500 ARS today
            , sampleExpense exchangeRate "018f0000-0000-7000-8000-000000000003" "Almuerzo" first 12500 ARS yesterday
            ]

        [] ->
            []


sampleExpense : Float -> String -> String -> Account -> Float -> Currency -> String -> Expense
sampleExpense exchangeRate id description account amount currency date =
    let
        converted =
            convert exchangeRate currency amount
    in
    { id = id
    , description = description
    , accountId = account.id
    , accountName = account.name
    , inputAmount = amount
    , inputCurrency = currency
    , exchangeRate = exchangeRate
    , ars = converted.ars
    , usd = converted.usd
    , date = date
    , deletedAt = Nothing
    }


filteredExpenses :
    { model
        | expenses : List Expense
        , filterWindow : FilterWindow
        , today : String
        , customStart : String
        , customEnd : String
    }
    -> List Expense
filteredExpenses model =
    List.filter (expenseMatchesFilter model) model.expenses


expenseMatchesFilter :
    { model
        | filterWindow : FilterWindow
        , today : String
        , customStart : String
        , customEnd : String
    }
    -> Expense
    -> Bool
expenseMatchesFilter model expense =
    case model.filterWindow of
        AllTime ->
            True

        ThisYear ->
            String.left 4 expense.date == String.left 4 model.today

        ThisMonth ->
            String.left 7 expense.date == String.left 7 model.today

        ThisWeek ->
            Date.weekStartIso expense.date == Date.weekStartIso model.today

        Today ->
            expense.date == model.today

        Custom ->
            withinCustomRange model.customStart model.customEnd expense.date


withinCustomRange : String -> String -> String -> Bool
withinCustomRange start end date =
    let
        afterStart =
            start == "" || date >= start

        beforeEnd =
            end == "" || date <= end
    in
    afterStart && beforeEnd


sortExpenses : SortField -> SortDirection -> List Expense -> List Expense
sortExpenses sortField sortDirection expenses =
    let
        sorted =
            case sortField of
                SortByDate ->
                    List.sortWith compareByDate expenses

                SortByAccount ->
                    List.sortWith compareByAccount expenses

                SortByDescription ->
                    List.sortWith compareByDescription expenses

                SortByExchangeRate ->
                    List.sortWith compareByExchangeRate expenses

                SortByPesos ->
                    List.sortWith compareByPesos expenses

                SortByDollars ->
                    List.sortWith compareByDollars expenses
    in
    case sortDirection of
        Ascending ->
            sorted

        Descending ->
            List.reverse sorted


compareByDate : Expense -> Expense -> Order
compareByDate left right =
    compareThen left.id right.id (compare left.date right.date)


compareByAccount : Expense -> Expense -> Order
compareByAccount left right =
    compareThen left.id right.id (compare (String.toLower left.accountName) (String.toLower right.accountName))


compareByDescription : Expense -> Expense -> Order
compareByDescription left right =
    compareThen left.id right.id (compare (String.toLower left.description) (String.toLower right.description))


compareByExchangeRate : Expense -> Expense -> Order
compareByExchangeRate left right =
    compareThen left.id right.id (compare left.exchangeRate right.exchangeRate)


compareByPesos : Expense -> Expense -> Order
compareByPesos left right =
    compareThen left.id right.id (compare left.ars right.ars)


compareByDollars : Expense -> Expense -> Order
compareByDollars left right =
    compareThen left.id right.id (compare left.usd right.usd)


compareThen : comparable -> comparable -> Order -> Order
compareThen left right order =
    case order of
        EQ ->
            compare left right

        _ ->
            order


currencyFromString : String -> Currency
currencyFromString currency =
    if currency == "USD" then
        USD

    else
        ARS


currencyToString : Currency -> String
currencyToString currency =
    case currency of
        ARS ->
            "ARS"

        USD ->
            "USD"
