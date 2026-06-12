module Main exposing (main)

import Browser
import Html exposing (Html, button, div, h1, h2, header, input, label, main_, option, p, section, select, strong, table, tbody, td, text, th, thead, tr)
import Html.Attributes exposing (attribute, class, step, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Json.Decode as Decode
import String
import Task
import Time


fallbackExchangeRate : Float
fallbackExchangeRate =
    1450


officialDollarUrl : String
officialDollarUrl =
    "https://dolarapi.com/v1/dolares/oficial"


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


type DateDisplay
    = NumericDate
    | LongDate


type ExchangeRateStatus
    = LoadingRate
    | LoadedRate String
    | FailedRate


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
    | GotExchangeRate (Result Http.Error OfficialDollar)
    | AddExpense


type alias OfficialDollar =
    { sale : Float
    , updatedAt : String
    }


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
    ( { form =
            { description = ""
            , amount = ""
            , person = Alice
            , currency = ARS
            , date = ""
            }
      , expenses = []
      , nextId = 1
      , error = ""
      , today = ""
      , filterWindow = AllTime
      , customStart = ""
      , customEnd = ""
      , dateDisplay = NumericDate
      , exchangeRate = fallbackExchangeRate
      , exchangeRateStatus = LoadingRate
      , zone = Time.utc
      }
    , Cmd.batch
        [ Task.perform identity (Task.map2 GotToday Time.here Time.now)
        , fetchOfficialDollar
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
                | form = setDate today model.form
                , today = today
                , expenses = sampleExpenses model.exchangeRate today
                , nextId = 5
                , zone = zone
              }
            , Cmd.none
            )

        UpdateDescription description ->
            ( { model | form = setDescription description model.form }, Cmd.none )

        UpdateAmount amount ->
            ( { model | form = setAmount amount model.form }, Cmd.none )

        UpdatePerson person ->
            ( { model | form = setPerson (personFromString person) model.form }, Cmd.none )

        UpdateCurrency currency ->
            ( { model | form = setCurrency (currencyFromString currency) model.form }, Cmd.none )

        UpdateDate date ->
            ( { model | form = setDate date model.form }, Cmd.none )

        SelectFilter filterWindow ->
            ( { model | filterWindow = filterWindow }, Cmd.none )

        UpdateCustomStart date ->
            ( { model | customStart = date, filterWindow = Custom }, Cmd.none )

        UpdateCustomEnd date ->
            ( { model | customEnd = date, filterWindow = Custom }, Cmd.none )

        SelectDateDisplay dateDisplay ->
            ( { model | dateDisplay = dateDisplay }, Cmd.none )

        GotExchangeRate result ->
            case result of
                Ok officialDollar ->
                    ( { model
                        | exchangeRate = officialDollar.sale
                        , exchangeRateStatus = LoadedRate officialDollar.updatedAt
                        , expenses = recalculateExpenses officialDollar.sale model.expenses
                      }
                    , Cmd.none
                    )

                Err _ ->
                    ( { model | exchangeRateStatus = FailedRate }, Cmd.none )

        AddExpense ->
            case buildExpense model.exchangeRate model.nextId model.form of
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


fetchOfficialDollar : Cmd Msg
fetchOfficialDollar =
    Http.get
        { url = officialDollarUrl
        , expect = Http.expectJson GotExchangeRate officialDollarDecoder
        }


officialDollarDecoder : Decode.Decoder OfficialDollar
officialDollarDecoder =
    Decode.map2 OfficialDollar
        (Decode.field "venta" Decode.float)
        (Decode.field "fechaActualizacion" Decode.string)


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

            else if dateFromIso form.date == Nothing then
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


view : Model -> Html Msg
view model =
    let
        visibleExpenses =
            filteredExpenses model
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
                [ expenseForm model
                , div [ class "content-stack" ]
                    [ expenseTable model visibleExpenses
                    ]
                ]
            ]
        ]


expenseForm : Model -> Html Msg
expenseForm model =
    section [ class "panel" ]
        [ h2 [ class "section-title" ] [ text "Nuevo gasto" ]
        , Html.form [ class "form-grid", onSubmit AddExpense ]
            [ label []
                [ text "Descripción"
                , input [ type_ "text", value model.form.description, onInput UpdateDescription ] []
                ]
            , div [ class "two-col" ]
                [ label []
                    [ text "Importe"
                    , input [ type_ "number", step "0.01", value model.form.amount, onInput UpdateAmount ] []
                    ]
                , label []
                    [ text "Divisa"
                    , select [ value (currencyToString model.form.currency), onInput UpdateCurrency ]
                        [ option [ value "ARS" ] [ text "AR$" ]
                        , option [ value "USD" ] [ text "U$D" ]
                        ]
                    ]
                ]
            , div [ class "two-col" ]
                [ label []
                    [ text "Nombre"
                    , select [ value (personToString model.form.person), onInput UpdatePerson ]
                        [ option [ value "Alice" ] [ text "Alice" ]
                        , option [ value "Bob" ] [ text "Bob" ]
                        ]
                    ]
                , label []
                    [ text "Fecha"
                    , input [ type_ "date", value model.form.date, onInput UpdateDate ] []
                    ]
                ]
            , conversionPreview model.exchangeRate model.form
            , exchangeRateView model
            , p [ class "error" ] [ text model.error ]
            , button [ class "primary", type_ "submit" ] [ text "Agregar gasto" ]
            ]
        ]


conversionPreview : Float -> Form -> Html Msg
conversionPreview exchangeRate form =
    case String.toFloat form.amount of
        Nothing ->
            text ""

        Just amount ->
            let
                converted =
                    convert exchangeRate form.currency amount
            in
            div [ class "conversion" ]
                [ text
                    ("Convertido: "
                        ++ formatMoney ARS converted.ars
                        ++ " / "
                        ++ formatMoney USD converted.usd
                    )
                ]


exchangeRateView : Model -> Html Msg
exchangeRateView model =
    let
        status =
            case model.exchangeRateStatus of
                LoadingRate ->
                    "Cargando cotización oficial..."

                LoadedRate updatedAt ->
                    "Actualizado: " ++ formatApiDate model.zone updatedAt

                FailedRate ->
                    "No se pudo cargar DolarApi. Usando cotización de respaldo."
    in
    div [ class "rate-status" ]
        [ p []
            [ strong [] [ text "1 U$D = " ]
            , strong [] [ text (formatMoney ARS model.exchangeRate) ]
            ]
        , p [ class "rate-status__meta" ] [ text status ]
        ]


expenseTable : Model -> List Expense -> Html Msg
expenseTable model expenses =
    section [ class "panel" ]
        [ h2 [ class "section-title" ] [ text "Gastos" ]
        , filterControls model
        , if List.isEmpty expenses then
            p [ class "empty" ] [ text "Todavía no hay gastos." ]

          else
            div [ class "table-wrap" ]
                [ table []
                    [ thead []
                        [ tr []
                            [ th [] [ text "Fecha" ]
                            , th [] [ text "Nombre" ]
                            , th [] [ text "Descripción" ]
                            , th [ class "numeric" ] [ text "Ingresado" ]
                            , th [ class "numeric" ] [ text "Pesos" ]
                            , th [ class "equivalence" ] [ text "=" ]
                            , th [ class "numeric" ] [ text "Dólar" ]
                            ]
                        ]
                    , tbody [] (List.map (expenseRow model.dateDisplay) (List.reverse expenses) ++ subtotalRows expenses)
                    ]
                ]
        ]


filterControls : Model -> Html Msg
filterControls model =
    div [ class "filters" ]
        [ div [ class "filter-buttons" ]
            [ filterButton model AllTime "Completo"
            , filterButton model ThisYear "Año"
            , filterButton model ThisMonth "Mes"
            , filterButton model ThisWeek "Semana"
            , filterButton model Today "Día"
            , filterButton model Custom "Personalizado"
            ]
        , div [ class "date-mode" ]
            [ p [] [ text "Fecha" ]
            , div [ class "filter-buttons" ]
                [ dateDisplayButton model NumericDate "DD/MM/AAAA"
                , dateDisplayButton model LongDate "Texto"
                ]
            ]
        , if model.filterWindow == Custom then
            div [ class "custom-range" ]
                [ label []
                    [ text "Desde"
                    , input [ type_ "date", value model.customStart, onInput UpdateCustomStart ] []
                    ]
                , label []
                    [ text "Hasta"
                    , input [ type_ "date", value model.customEnd, onInput UpdateCustomEnd ] []
                    ]
                ]

          else
            text ""
        ]


filterButton : Model -> FilterWindow -> String -> Html Msg
filterButton model filterWindow labelText =
    button
        [ type_ "button"
        , class
            (if model.filterWindow == filterWindow then
                "filter-button filter-button--active"

             else
                "filter-button"
            )
        , onClick (SelectFilter filterWindow)
        ]
        [ text labelText ]


dateDisplayButton : Model -> DateDisplay -> String -> Html Msg
dateDisplayButton model dateDisplay labelText =
    button
        [ type_ "button"
        , class
            (if model.dateDisplay == dateDisplay then
                "filter-button filter-button--active"

             else
                "filter-button"
            )
        , onClick (SelectDateDisplay dateDisplay)
        ]
        [ text labelText ]


expenseRow : DateDisplay -> Expense -> Html Msg
expenseRow dateDisplay expense =
    tr []
        [ td [] [ text (formatDate dateDisplay expense.date) ]
        , td [] [ text (personToString expense.person) ]
        , td [] [ text expense.description ]
        , td [ class "numeric" ] [ text (formatMoney expense.inputCurrency expense.inputAmount) ]
        , td [ class "numeric" ] [ text (formatMoney ARS expense.ars) ]
        , td [ class "equivalence" ] [ text "=" ]
        , td [ class "numeric" ] [ text (formatMoney USD expense.usd) ]
        ]


subtotalRows : List Expense -> List (Html Msg)
subtotalRows expenses =
    let
        aliceTotal =
            summarizeMoney (expensesFor Alice expenses)

        bobTotal =
            summarizeMoney (expensesFor Bob expenses)

        grandTotal =
            summarizeMoney expenses
    in
    [ totalRow "Subtotal Alice" "subtotal" aliceTotal
    , totalRow "Subtotal Bob" "subtotal" bobTotal
    , totalRow "Total" "grand-total" grandTotal
    ]


totalRow : String -> String -> MoneyTotal -> Html Msg
totalRow labelText rowClass total =
    tr [ class rowClass ]
        [ td [ attribute "colspan" "4" ] [ text labelText ]
        , td [ class "numeric" ] [ text (formatMoney ARS total.ars) ]
        , td [ class "equivalence" ] [ text "=" ]
        , td [ class "numeric" ] [ text (formatMoney USD total.usd) ]
        ]


type alias MoneyTotal =
    { ars : Float
    , usd : Float
    }


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
            addDays -1 today

        lastWeek =
            addDays -7 today
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


filteredExpenses : Model -> List Expense
filteredExpenses model =
    List.filter (expenseMatchesFilter model) model.expenses


expenseMatchesFilter : Model -> Expense -> Bool
expenseMatchesFilter model expense =
    case model.filterWindow of
        AllTime ->
            True

        ThisYear ->
            String.left 4 expense.date == String.left 4 model.today

        ThisMonth ->
            String.left 7 expense.date == String.left 7 model.today

        ThisWeek ->
            weekStartIso expense.date == weekStartIso model.today

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


weekStartIso : String -> String
weekStartIso iso =
    case dateFromIso iso of
        Nothing ->
            iso

        Just date ->
            let
                days =
                    daysFromCivil date.year date.month date.day

                monday =
                    days - modBy 7 (days + 3)
            in
            civilToIso (civilFromDays monday)


addDays : Int -> String -> String
addDays offset iso =
    case dateFromIso iso of
        Nothing ->
            iso

        Just date ->
            civilToIso (civilFromDays (daysFromCivil date.year date.month date.day + offset))


type alias CivilDate =
    { year : Int
    , month : Int
    , day : Int
    }


dateFromIso : String -> Maybe CivilDate
dateFromIso iso =
    case String.split "-" iso of
        [ yearString, monthString, dayString ] ->
            Maybe.map3 CivilDate
                (String.toInt yearString)
                (String.toInt monthString)
                (String.toInt dayString)

        _ ->
            Nothing


dateToIso : Time.Zone -> Time.Posix -> String
dateToIso zone posix =
    String.fromInt (Time.toYear zone posix)
        ++ "-"
        ++ pad2 (monthToNumber (Time.toMonth zone posix))
        ++ "-"
        ++ pad2 (Time.toDay zone posix)


civilToIso : CivilDate -> String
civilToIso date =
    String.fromInt date.year ++ "-" ++ pad2 date.month ++ "-" ++ pad2 date.day


formatDate : DateDisplay -> String -> String
formatDate dateDisplay iso =
    case dateFromIso iso of
        Nothing ->
            iso

        Just date ->
            case dateDisplay of
                NumericDate ->
                    pad2 date.day ++ "/" ++ pad2 date.month ++ "/" ++ String.fromInt date.year

                LongDate ->
                    weekdayName date
                        ++ " "
                        ++ String.fromInt date.day
                        ++ " de "
                        ++ monthName date.month
                        ++ " de "
                        ++ String.fromInt date.year


formatApiDate : Time.Zone -> String -> String
formatApiDate zone timestamp =
    case parseApiTimestamp timestamp of
        Nothing ->
            timestamp

        Just posix ->
            dateToIso zone posix
                |> formatDate NumericDate
                |> (\date -> date ++ " " ++ pad2 (Time.toHour zone posix) ++ ":" ++ pad2 (Time.toMinute zone posix))


parseApiTimestamp : String -> Maybe Time.Posix
parseApiTimestamp timestamp =
    let
        datePart =
            String.left 10 timestamp

        timePart =
            timestamp
                |> String.dropLeft 11
                |> String.left 8
    in
    case ( dateFromIso datePart, String.split ":" timePart ) of
        ( Just date, [ hourString, minuteString, secondString ] ) ->
            Maybe.map3
                (\hour minute second ->
                    let
                        millis =
                            ((daysFromCivil date.year date.month date.day * 24 + hour) * 60 + minute)
                                * 60
                                * 1000
                                + second
                                * 1000
                    in
                    Time.millisToPosix millis
                )
                (String.toInt hourString)
                (String.toInt minuteString)
                (String.toInt secondString)

        _ ->
            Nothing


weekdayName : CivilDate -> String
weekdayName date =
    case modBy 7 (daysFromCivil date.year date.month date.day + 3) of
        0 ->
            "Lunes"

        1 ->
            "Martes"

        2 ->
            "Miércoles"

        3 ->
            "Jueves"

        4 ->
            "Viernes"

        5 ->
            "Sábado"

        _ ->
            "Domingo"


monthName : Int -> String
monthName month =
    case month of
        1 ->
            "enero"

        2 ->
            "febrero"

        3 ->
            "marzo"

        4 ->
            "abril"

        5 ->
            "mayo"

        6 ->
            "junio"

        7 ->
            "julio"

        8 ->
            "agosto"

        9 ->
            "septiembre"

        10 ->
            "octubre"

        11 ->
            "noviembre"

        _ ->
            "diciembre"


pad2 : Int -> String
pad2 number =
    if number < 10 then
        "0" ++ String.fromInt number

    else
        String.fromInt number


monthToNumber : Time.Month -> Int
monthToNumber month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12


daysFromCivil : Int -> Int -> Int -> Int
daysFromCivil year month day =
    let
        adjustedYear =
            if month <= 2 then
                year - 1

            else
                year

        era =
            floor (toFloat adjustedYear / 400)

        yearOfEra =
            adjustedYear - era * 400

        monthPrime =
            if month > 2 then
                month - 3

            else
                month + 9

        dayOfYear =
            (153 * monthPrime + 2) // 5 + day - 1

        dayOfEra =
            yearOfEra * 365 + yearOfEra // 4 - yearOfEra // 100 + dayOfYear
    in
    era * 146097 + dayOfEra - 719468


civilFromDays : Int -> CivilDate
civilFromDays days =
    let
        z =
            days + 719468

        era =
            floor (toFloat z / 146097)

        dayOfEra =
            z - era * 146097

        yearOfEra =
            (dayOfEra - dayOfEra // 1460 + dayOfEra // 36524 - dayOfEra // 146096) // 365

        year =
            yearOfEra + era * 400

        dayOfYear =
            dayOfEra - (365 * yearOfEra + yearOfEra // 4 - yearOfEra // 100)

        monthPrime =
            (5 * dayOfYear + 2) // 153

        day =
            dayOfYear - (153 * monthPrime + 2) // 5 + 1

        month =
            if monthPrime < 10 then
                monthPrime + 3

            else
                monthPrime - 9

        finalYear =
            if month <= 2 then
                year + 1

            else
                year
    in
    { year = finalYear, month = month, day = day }


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


formatMoney : Currency -> Float -> String
formatMoney currency amount =
    let
        prefix =
            case currency of
                ARS ->
                    "AR$ "

                USD ->
                    "U$D "
    in
    prefix ++ formatFloat amount


formatFloat : Float -> String
formatFloat amount =
    let
        cents =
            round (amount * 100)

        whole =
            cents // 100

        decimal =
            abs (modBy 100 cents)
    in
    formatThousands whole ++ "," ++ pad2 decimal


formatThousands : Int -> String
formatThousands number =
    if number < 1000 then
        String.fromInt number

    else
        formatThousands (number // 1000) ++ "." ++ pad3 (modBy 1000 number)


pad3 : Int -> String
pad3 number =
    if number < 10 then
        "00" ++ String.fromInt number

    else if number < 100 then
        "0" ++ String.fromInt number

    else
        String.fromInt number
