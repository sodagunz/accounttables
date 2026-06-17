module Api.Dolar exposing
    ( ExchangeRateStatus(..)
    , OfficialDollar
    , fetchOfficialDollar
    )

import Http
import Json.Decode as Decode


ambitoDolaresUrl : String
ambitoDolaresUrl =
    "https://dolarapi.com/v1/ambito/dolares"


type ExchangeRateStatus
    = LoadingRate
    | LoadedRate String
    | FailedRate


type alias OfficialDollar =
    { sale : Float
    , updatedAt : String
    }


fetchOfficialDollar : (Result Http.Error OfficialDollar -> msg) -> Cmd msg
fetchOfficialDollar toMsg =
    Http.get
        { url = ambitoDolaresUrl
        , expect = Http.expectJson toMsg officialDollarDecoder
        }


officialDollarDecoder : Decode.Decoder OfficialDollar
officialDollarDecoder =
    Decode.list casaDecoder
        |> Decode.andThen
            (\items ->
                case List.filter (\item -> item.casa == "oficial") items of
                    [ oficial ] ->
                        Decode.succeed
                            { sale = oficial.venta
                            , updatedAt = oficial.fechaActualizacion
                            }

                    _ ->
                        Decode.fail "No se encontró la cotización oficial"
            )


type alias Casa =
    { casa : String
    , venta : Float
    , fechaActualizacion : String
    }


casaDecoder : Decode.Decoder Casa
casaDecoder =
    Decode.map3 Casa
        (Decode.field "casa" Decode.string)
        (Decode.field "venta" Decode.float)
        (Decode.field "fechaActualizacion" Decode.string)
