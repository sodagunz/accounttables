module Accounting exposing
    ( Account
    , Currency(..)
    , Movement
    , FilterWindow(..)
    , Form
    , MoneyTotal
    , MovementType(..)
    , SortDirection(..)
    , SortField(..)
    , addMoney
    , buildMovement
    , cashflowFor
    , convert
    , currencyFromString
    , currencyToString
    , descriptionDisplay
    , emptyForm
    , emptyMoney
    , movementMatchesFilter
    , movementsFor
    , fallbackExchangeRate
    , filteredMovements
    , movementTypeFromString
    , movementTypeToString
    , sampleMovements
    , setAccount
    , setAmount
    , setCurrency
    , setDate
    , setDescription
    , setMovementType
    , movementToForm
    , sortMovements
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


type MovementType
    = ExpenseMovement
    | IncomeMovement


type alias Movement =
    { id : String
    , movementType : MovementType
    , description : Maybe String
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
    , movementType : MovementType
    , editingId : Maybe String
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
    , movementType = ExpenseMovement
    , editingId = Nothing
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

setMovementType : MovementType -> Form -> Form
setMovementType movementType form =
    { form | movementType = movementType }


movementToForm : Movement -> Form -> Form
movementToForm movement form =
    { description = movement.description |> Maybe.withDefault ""
    , amount = String.fromFloat movement.inputAmount
    , accountId = movement.accountId
    , currency = movement.inputCurrency
    , date = movement.date
    , movementType = movement.movementType
    , editingId = Just movement.id
    }


buildMovement : Float -> String -> List Account -> Form -> Result String Movement
buildMovement exchangeRate id accounts form =
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
            if amount <= 0 then
                Err "El monto debe ser mayor que cero."

            else if Date.dateFromIso form.date == Nothing then
                Err "Ingresa una fecha válida."

            else
                case selectedAccount of
                    Nothing ->
                        Err "Selecciona una cuenta."

                    Just account ->
                        let
                            converted =
                                cashflowFor form.movementType exchangeRate form.currency amount
                        in
                        Ok
                            { id = id
                            , movementType = form.movementType
                            , description =
                                if description == "" then
                                    Nothing

                                else
                                    Just description
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


cashflowFor : MovementType -> Float -> Currency -> Float -> { ars : Float, usd : Float }
cashflowFor movementType exchangeRate currency inputAmount =
    let
        converted =
            convert exchangeRate currency (abs inputAmount)

        multiplier =
            movementMultiplier movementType
    in
    { ars = converted.ars * multiplier
    , usd = converted.usd * multiplier
    }


movementMultiplier : MovementType -> Float
movementMultiplier movementType =
    case movementType of
        ExpenseMovement ->
            -1

        IncomeMovement ->
            1


emptyMoney : MoneyTotal
emptyMoney =
    { ars = 0, usd = 0 }


summarizeMoney : List Movement -> MoneyTotal
summarizeMoney expenses =
    List.foldl addMoney emptyMoney expenses


addMoney : Movement -> MoneyTotal -> MoneyTotal
addMoney movement total =
    { ars = total.ars + movement.ars
    , usd = total.usd + movement.usd
    }


movementsFor : Account -> List Movement -> List Movement
movementsFor account expenses =
    List.filter (\expense -> expense.accountId == account.id) expenses


sampleMovements : Float -> String -> List Account -> List Movement
sampleMovements exchangeRate today accounts =
    let
        yesterday =
            Date.addDays -1 today

        lastWeek =
            Date.addDays -7 today
    in
    case accounts of
        first :: second :: _ ->
            [ sampleMovement exchangeRate "018f0000-0000-7000-8000-000000000001" "Supermercado" first 28500 ARS today
            , sampleMovement exchangeRate "018f0000-0000-7000-8000-000000000002" "Nafta" second 42 USD today
            , sampleMovement exchangeRate "018f0000-0000-7000-8000-000000000003" "Almuerzo" first 12500 ARS yesterday
            , sampleMovement exchangeRate "018f0000-0000-7000-8000-000000000004" "Librería" second 18500 ARS lastWeek
            ]

        first :: [] ->
            [ sampleMovement exchangeRate "018f0000-0000-7000-8000-000000000001" "Supermercado" first 28500 ARS today
            , sampleMovement exchangeRate "018f0000-0000-7000-8000-000000000003" "Almuerzo" first 12500 ARS yesterday
            ]

        [] ->
            []


sampleMovement : Float -> String -> String -> Account -> Float -> Currency -> String -> Movement
sampleMovement exchangeRate id description account amount currency date =
    let
        converted =
            cashflowFor ExpenseMovement exchangeRate currency amount
    in
    { id = id
    , movementType = ExpenseMovement
    , description = Just description
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


filteredMovements :
    { model
        | expenses : List Movement
        , filterWindow : FilterWindow
        , today : String
    }
    -> List Movement
filteredMovements model =
    List.filter (movementMatchesFilter model) model.expenses


movementMatchesFilter :
    { model
        | filterWindow : FilterWindow
        , today : String
    }
    -> Movement
    -> Bool
movementMatchesFilter model movement =
    case model.filterWindow of
        AllTime ->
            True

        ThisYear ->
            String.left 4 movement.date == String.left 4 model.today

        ThisMonth ->
            String.left 7 movement.date == String.left 7 model.today

        ThisWeek ->
            Date.weekStartIso movement.date == Date.weekStartIso model.today

        Today ->
            movement.date == model.today


sortMovements : SortField -> SortDirection -> List Movement -> List Movement
sortMovements sortField sortDirection expenses =
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


compareByDate : Movement -> Movement -> Order
compareByDate left right =
    compareThen left.id right.id (compare left.date right.date)


compareByAccount : Movement -> Movement -> Order
compareByAccount left right =
    compareThen left.id right.id (compare (String.toLower left.accountName) (String.toLower right.accountName))


compareByDescription : Movement -> Movement -> Order
compareByDescription left right =
    compareThen left.id right.id (compare (descriptionText left) (descriptionText right))


descriptionText : Movement -> String
descriptionText movement =
    movement.description
        |> Maybe.withDefault ""
        |> String.toLower


descriptionDisplay : Movement -> String
descriptionDisplay movement =
    case Maybe.map String.trim movement.description of
        Just description ->
            if description == "" then
                "-"

            else
                description

        Nothing ->
            "-"


compareByExchangeRate : Movement -> Movement -> Order
compareByExchangeRate left right =
    compareThen left.id right.id (compare left.exchangeRate right.exchangeRate)


compareByPesos : Movement -> Movement -> Order
compareByPesos left right =
    compareThen left.id right.id (compare left.ars right.ars)


compareByDollars : Movement -> Movement -> Order
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


movementTypeFromString : String -> MovementType
movementTypeFromString movementType =
    case movementType of
        "Expense" ->
            ExpenseMovement

        "Income" ->
            IncomeMovement

        _ ->
            ExpenseMovement


movementTypeToString : MovementType -> String
movementTypeToString movementType =
    case movementType of
        ExpenseMovement ->
            "Expense"

        IncomeMovement ->
            "Income"
