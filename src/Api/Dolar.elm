module Api.Dolar exposing (ExchangeRateStatus(..))


type ExchangeRateStatus
    = LoadingRate
    | LoadedRate
    | FailedRate String
