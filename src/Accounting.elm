module Accounting exposing
    ( Account
    , Currency(..)
    , FilterWindow(..)
    , Form
    , MoneyTotal
    , Movement
    , MovementType(..)
    , SortDirection(..)
    , SortField(..)
    , buildMovement
    , cashflowFor
    , currencyFromString
    , currencyToString
    , descriptionDisplay
    , emptyForm
    , fallbackExchangeRate
    , filteredMovements
    , invoiceTotal
    , isCashflowMovement
    , isInvoiceMovement
    , isInvoiceRelatedCashflow
    , movementToForm
    , movementTypeFromString
    , movementTypeToString
    , movementsFor
    , negateMoney
    , setAccount
    , setAmount
    , setCurrency
    , setDate
    , setDescription
    , setDocumentNumber
    , setMovementType
    , setRelatedToInvoice
    , sortMovements
    , summarizeMoney
    )

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
    | SupplierInvoiceMovement
    | SupplierCreditNoteMovement


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
    , relatedToInvoice : Bool
    , documentNumber : Maybe String
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
    , relatedToInvoice : Bool
    , documentNumber : String
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
    , relatedToInvoice = False
    , documentNumber = ""
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


setRelatedToInvoice : Bool -> Form -> Form
setRelatedToInvoice relatedToInvoice form =
    { form | relatedToInvoice = relatedToInvoice }


setDocumentNumber : String -> Form -> Form
setDocumentNumber documentNumber form =
    { form | documentNumber = documentNumber }


movementToForm : Movement -> Form
movementToForm movement =
    { description = movement.description |> Maybe.withDefault ""
    , amount = String.fromFloat movement.inputAmount
    , accountId = movement.accountId
    , currency = movement.inputCurrency
    , date = movement.date
    , movementType = movement.movementType
    , editingId = Just movement.id
    , relatedToInvoice = movement.relatedToInvoice
    , documentNumber = movement.documentNumber |> Maybe.withDefault ""
    }


buildMovement : Float -> String -> List Account -> Form -> Result String Movement
buildMovement exchangeRate id accounts form =
    case String.toFloat form.amount of
        Nothing ->
            Err "Ingresa un monto válido."

        Just amount ->
            if amount <= 0 then
                Err "El monto debe ser mayor que cero."

            else if Date.dateFromIso form.date == Nothing then
                Err "Ingresa una fecha válida."

            else
                let
                    selectedAccount : Maybe Account
                    selectedAccount =
                        accounts
                            |> List.filter (\account -> account.id == form.accountId && account.deletedAt == Nothing)
                            |> List.head
                in
                case selectedAccount of
                    Nothing ->
                        Err "Selecciona una cuenta."

                    Just account ->
                        let
                            description : String
                            description =
                                String.trim form.description

                            converted : { ars : Float, usd : Float }
                            converted =
                                cashflowFor form.movementType exchangeRate form.currency amount

                            isInvoiceType : Bool
                            isInvoiceType =
                                form.movementType
                                    == SupplierInvoiceMovement
                                    || form.movementType
                                    == SupplierCreditNoteMovement

                            resolvedDocumentNumber : Maybe String
                            resolvedDocumentNumber =
                                if isInvoiceType then
                                    let
                                        trimmed : String
                                        trimmed =
                                            String.trim form.documentNumber
                                    in
                                    if trimmed == "" then
                                        Nothing

                                    else
                                        Just trimmed

                                else
                                    Nothing
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
                            , relatedToInvoice =
                                if isInvoiceType then
                                    False

                                else
                                    form.relatedToInvoice
                            , documentNumber = resolvedDocumentNumber
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
        converted : { ars : Float, usd : Float }
        converted =
            convert exchangeRate currency (abs inputAmount)

        multiplier : Float
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

        SupplierInvoiceMovement ->
            -1

        SupplierCreditNoteMovement ->
            1


isCashflowMovement : Movement -> Bool
isCashflowMovement movement =
    movement.movementType == ExpenseMovement || movement.movementType == IncomeMovement


isInvoiceMovement : Movement -> Bool
isInvoiceMovement movement =
    movement.movementType == SupplierInvoiceMovement || movement.movementType == SupplierCreditNoteMovement


isInvoiceRelatedCashflow : Movement -> Bool
isInvoiceRelatedCashflow movement =
    isCashflowMovement movement && movement.relatedToInvoice


invoiceTotal : List Movement -> List Movement -> MoneyTotal
invoiceTotal invoices relatedCashflows =
    let
        invoiceSum : MoneyTotal
        invoiceSum =
            summarizeMoney invoices

        paymentSum : MoneyTotal
        paymentSum =
            summarizeMoney relatedCashflows
    in
    { ars = invoiceSum.ars - paymentSum.ars
    , usd = invoiceSum.usd - paymentSum.usd
    }


negateMoney : MoneyTotal -> MoneyTotal
negateMoney total =
    { ars = -total.ars
    , usd = -total.usd
    }


emptyMoney : MoneyTotal
emptyMoney =
    { ars = 0, usd = 0 }


summarizeMoney : List Movement -> MoneyTotal
summarizeMoney movements =
    List.foldl addMoney emptyMoney movements


addMoney : Movement -> MoneyTotal -> MoneyTotal
addMoney movement total =
    { ars = total.ars + movement.ars
    , usd = total.usd + movement.usd
    }


movementsFor : Account -> List Movement -> List Movement
movementsFor account movements =
    List.filter (\movement -> movement.accountId == account.id) movements


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
sortMovements sortField sortDirection movements =
    let
        sorted : List Movement
        sorted =
            case sortField of
                SortByDate ->
                    List.sortWith compareByDate movements

                SortByAccount ->
                    List.sortWith compareByAccount movements

                SortByDescription ->
                    List.sortWith compareByDescription movements

                SortByExchangeRate ->
                    List.sortWith compareByExchangeRate movements

                SortByPesos ->
                    List.sortWith compareByPesos movements

                SortByDollars ->
                    List.sortWith compareByDollars movements
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

        "SupplierInvoice" ->
            SupplierInvoiceMovement

        "SupplierCreditNote" ->
            SupplierCreditNoteMovement

        _ ->
            ExpenseMovement


movementTypeToString : MovementType -> String
movementTypeToString movementType =
    case movementType of
        ExpenseMovement ->
            "Expense"

        IncomeMovement ->
            "Income"

        SupplierInvoiceMovement ->
            "SupplierInvoice"

        SupplierCreditNoteMovement ->
            "SupplierCreditNote"
