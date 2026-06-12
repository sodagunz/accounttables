module Util.Date exposing
    ( CivilDate
    , DateDisplay(..)
    , addDays
    , dateFromIso
    , dateToIso
    , formatApiDate
    , formatDate
    , pad2
    , weekStartIso
    )

import String
import Time


type DateDisplay
    = NumericDate
    | LongDate


type alias CivilDate =
    { year : Int
    , month : Int
    , day : Int
    }


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
