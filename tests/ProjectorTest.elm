module ProjectorTest exposing (suite)

import Accounting exposing (Currency(..), MovementType(..))
import Events exposing (Event(..))
import Expect
import Projector
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Projector"
        [ test "sorts events by sequence, applies updates, then deletions" <|
            \_ ->
                let
                    events : List Event
                    events =
                        [ MovementDeletedEvent 3 { movementId = "movement-1" }
                        , MovementUpdatedEvent 2
                            { movementId = "movement-1"
                            , movementType = IncomeMovement
                            , description = Just "Venta actualizada"
                            , accountId = "bank"
                            , accountName = "Banco"
                            , inputAmount = 20
                            , inputCurrency = USD
                            , exchangeRate = 1000
                            , ars = 20000
                            , usd = 20
                            , date = "2026-06-16"
                            }
                        , MovementCreatedEvent 1
                            { id = "movement-1"
                            , movementType = ExpenseMovement
                            , description = Just "Original"
                            , accountId = "cash"
                            , accountName = "Caja"
                            , inputAmount = 10
                            , inputCurrency = ARS
                            , exchangeRate = 1000
                            , ars = -10
                            , usd = -0.01
                            , date = "2026-06-15"
                            }
                        ]
                in
                case Projector.projectEvents events of
                    [ expense ] ->
                        Expect.all
                            [ \actual -> Expect.equal "movement-1" actual.id
                            , \actual -> Expect.equal IncomeMovement actual.movementType
                            , \actual -> Expect.equal (Just "Venta actualizada") actual.description
                            , \actual -> Expect.equal "bank" actual.accountId
                            , \actual -> Expect.within (Expect.Absolute 0.0001) 20000 actual.ars
                            , \actual -> Expect.equal (Just "deleted") actual.deletedAt
                            ]
                            expense

                    projected ->
                        Expect.fail ("Expected one projected movement, got " ++ String.fromInt (List.length projected))
        ]
