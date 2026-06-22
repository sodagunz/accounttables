module Util.Date exposing
    ( CivilDate
    , DateDisplay(..)
    , dateFromIso
    , dateToIso
    , formatDate
    , pad2
    , weekStartIso
    )

import Date as Calendar exposing (Interval(..))
import Time exposing (Month(..), Weekday(..))


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
    iso
        |> Calendar.fromIsoString
        |> Result.map (Calendar.floor Monday >> Calendar.toIsoString)
        |> Result.withDefault iso


dateFromIso : String -> Maybe CivilDate
dateFromIso iso =
    iso
        |> Calendar.fromIsoString
        |> Result.map toCivilDate
        |> Result.toMaybe


dateToIso : Time.Zone -> Time.Posix -> String
dateToIso zone posix =
    Calendar.fromPosix zone posix
        |> Calendar.toIsoString


toCivilDate : Calendar.Date -> CivilDate
toCivilDate date =
    { year = Calendar.year date
    , month = Calendar.monthNumber date
    , day = Calendar.day date
    }


formatDate : DateDisplay -> String -> String
formatDate dateDisplay iso =
    case Calendar.fromIsoString iso of
        Err _ ->
            iso

        Ok date ->
            case dateDisplay of
                NumericDate ->
                    Calendar.formatWithLanguage spanish "dd/MM/y" date

                LongDate ->
                    Calendar.formatWithLanguage spanish "EEEE d 'de' MMMM 'de' y" date


spanish : Calendar.Language
spanish =
    { monthName = spanishMonthName
    , monthNameShort = spanishMonthName >> String.left 3
    , weekdayName = spanishWeekdayName
    , weekdayNameShort = spanishWeekdayName >> String.left 3
    , dayWithSuffix = String.fromInt
    }


spanishMonthName : Time.Month -> String
spanishMonthName month =
    case month of
        Jan ->
            "enero"

        Feb ->
            "febrero"

        Mar ->
            "marzo"

        Apr ->
            "abril"

        May ->
            "mayo"

        Jun ->
            "junio"

        Jul ->
            "julio"

        Aug ->
            "agosto"

        Sep ->
            "septiembre"

        Oct ->
            "octubre"

        Nov ->
            "noviembre"

        Dec ->
            "diciembre"


spanishWeekdayName : Time.Weekday -> String
spanishWeekdayName weekday =
    case weekday of
        Mon ->
            "Lunes"

        Tue ->
            "Martes"

        Wed ->
            "Miércoles"

        Thu ->
            "Jueves"

        Fri ->
            "Viernes"

        Sat ->
            "Sábado"

        Sun ->
            "Domingo"


pad2 : Int -> String
pad2 number =
    if number < 10 then
        "0" ++ String.fromInt number

    else
        String.fromInt number
