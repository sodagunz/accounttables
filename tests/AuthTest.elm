module AuthTest exposing (suite)

import Auth exposing (AuthState(..))
import Expect
import Json.Encode as Encode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Auth"
        [ test "decodes signed-in users" <|
            \_ ->
                let
                    payload =
                        Encode.object
                            [ ( "status", Encode.string "signed-in" )
                            , ( "user"
                              , Encode.object
                                    [ ( "uid", Encode.string "user-1" )
                                    , ( "displayName", Encode.string "Ana" )
                                    , ( "email", Encode.string "ana@example.com" )
                                    , ( "photoUrl", Encode.string "" )
                                    ]
                              )
                            ]
                in
                case Auth.decodeAuthState payload of
                    SignedIn user ->
                        Expect.all
                            [ \actual -> Expect.equal "user-1" actual.uid
                            , \actual -> Expect.equal "Ana" actual.displayName
                            , \actual -> Expect.equal "ana@example.com" actual.email
                            ]
                            user

                    decoded ->
                        Expect.fail "Expected SignedIn, got different auth state"
        ]
