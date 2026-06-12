module Accounting exposing
    ( Currency(..)
    , Expense
    , FilterWindow(..)
    , Form
    , MoneyTotal
    , Person(..)
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
    , personFromString
    , personToString
    , recalculateExpenses
    , sampleExpenses
    , setAmount
    , setCurrency
    , setDate
    , setDescription
    , setPerson
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


type Person
    = Alice
    | Bob


type FilterWindow
    = AllTime
    | ThisYear
    | ThisMonth
    | ThisWeek
    | Today
    | Custom


type alias Expense =
    { id : Int
    , description : String
    , person : Person
    , inputAmount : Float
    , inputCurrency : Currency
    , ars : Float
    , usd : Float
    , date : String
    }


type alias Form =
    { description : String
    , amount : String
    , person : Person
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
    , person = Alice
    , currency = ARS
    , date = ""
    }


setDescription : String -> Form -> Form
setDescription description form =
    { form | description = description }


setAmount : String -> Form -> Form
setAmount amount form =
    { form | amount = amount }


setPerson : Person -> Form -> Form
setPerson person form =
    { form | person = person }


setCurrency : Currency -> Form -> Form
setCurrency currency form =
    { form | currency = currency }


setDate : String -> Form -> Form
setDate date form =
    { form | date = date }


buildExpense : Float -> Int -> Form -> Result String Expense
buildExpense exchangeRate id form =
    let
        description =
            String.trim form.description
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
                let
                    converted =
                        convert exchangeRate form.currency amount
                in
                Ok
                    { id = id
                    , description = description
                    , person = form.person
                    , inputAmount = amount
                    , inputCurrency = form.currency
                    , ars = converted.ars
                    , usd = converted.usd
                    , date = form.date
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


expensesFor : Person -> List Expense -> List Expense
expensesFor person expenses =
    List.filter (\expense -> expense.person == person) expenses


sampleExpenses : Float -> String -> List Expense
sampleExpenses exchangeRate today =
    let
        yesterday =
            Date.addDays -1 today

        lastWeek =
            Date.addDays -7 today
    in
    [ sampleExpense exchangeRate 1 "Supermercado" Alice 28500 ARS today
    , sampleExpense exchangeRate 2 "Nafta" Bob 42 USD today
    , sampleExpense exchangeRate 3 "Almuerzo" Alice 12500 ARS yesterday
    , sampleExpense exchangeRate 4 "Librería" Bob 18500 ARS lastWeek
    ]


sampleExpense : Float -> Int -> String -> Person -> Float -> Currency -> String -> Expense
sampleExpense exchangeRate id description person amount currency date =
    let
        converted =
            convert exchangeRate currency amount
    in
    { id = id
    , description = description
    , person = person
    , inputAmount = amount
    , inputCurrency = currency
    , ars = converted.ars
    , usd = converted.usd
    , date = date
    }


recalculateExpenses : Float -> List Expense -> List Expense
recalculateExpenses exchangeRate expenses =
    List.map (recalculateExpense exchangeRate) expenses


recalculateExpense : Float -> Expense -> Expense
recalculateExpense exchangeRate expense =
    let
        converted =
            convert exchangeRate expense.inputCurrency expense.inputAmount
    in
    { expense | ars = converted.ars, usd = converted.usd }


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


personFromString : String -> Person
personFromString person =
    if person == "Bob" then
        Bob

    else
        Alice


personToString : Person -> String
personToString person =
    case person of
        Alice ->
            "Alice"

        Bob ->
            "Bob"
