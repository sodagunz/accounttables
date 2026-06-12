module Api.Dolar exposing
    ( ExchangeRateStatus(..)
    , OfficialDollar
    , fetchOfficialDollar
    )

import Http
import Json.Decode as Decode


officialDollarUrl : String
officialDollarUrl =
    "https://dolarapi.com/v1/dolares/oficial"


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
        { url = officialDollarUrl
        , expect = Http.expectJson toMsg officialDollarDecoder
        }


officialDollarDecoder : Decode.Decoder OfficialDollar
officialDollarDecoder =
    Decode.map2 OfficialDollar
        (Decode.field "venta" Decode.float)
        (Decode.field "fechaActualizacion" Decode.string)
