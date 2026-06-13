module Auth exposing
    ( AuthState(..)
    , User
    , decodeAuthState
    )

import Json.Decode as Decode


type AuthState
    = AuthLoading
    | AuthUnconfigured
    | SignedOut
    | SignedIn User
    | AuthError String


type alias User =
    { uid : String
    , displayName : String
    , email : String
    , photoUrl : String
    }


decodeAuthState : Decode.Value -> AuthState
decodeAuthState value =
    Decode.decodeValue authStateDecoder value
        |> Result.withDefault (AuthError "No se pudo leer el estado de autenticación.")


authStateDecoder : Decode.Decoder AuthState
authStateDecoder =
    Decode.field "status" Decode.string
        |> Decode.andThen authStateFromStatus


authStateFromStatus : String -> Decode.Decoder AuthState
authStateFromStatus status =
    case status of
        "unconfigured" ->
            Decode.succeed AuthUnconfigured

        "signed-out" ->
            Decode.succeed SignedOut

        "signed-in" ->
            Decode.map SignedIn (Decode.field "user" userDecoder)

        "error" ->
            Decode.map AuthError (Decode.field "message" Decode.string)

        _ ->
            Decode.succeed (AuthError "Estado de autenticación desconocido.")


userDecoder : Decode.Decoder User
userDecoder =
    Decode.map4 User
        (Decode.field "uid" Decode.string)
        (Decode.field "displayName" Decode.string)
        (Decode.field "email" Decode.string)
        (Decode.field "photoUrl" Decode.string)
