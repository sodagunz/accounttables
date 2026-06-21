module AllocationTest exposing (suite)

import Allocation exposing (AllocationStrategy(..), AutoSelectionReason(..), MigrationSelectionReason(..), TargetSelectionSource(..))
import Expect
import Json.Decode as Decode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Allocation"
        [ test "round-trips auto-selected allocation intent" <|
            \_ ->
                let
                    intent : Allocation.AllocationIntent
                    intent =
                        { targetIds = [ "inv-1", "inv-2" ]
                        , targetSelectionSource = AutoSelectedTargets AutoAllOpenDocuments
                        , strategy = OldestDueFirstThenOverpayOldest
                        }
                in
                Allocation.allocationIntentEncoder intent
                    |> Decode.decodeValue Allocation.allocationIntentDecoder
                    |> Expect.equal (Ok intent)
        , test "round-trips migration-selected allocation intent" <|
            \_ ->
                let
                    intent : Allocation.AllocationIntent
                    intent =
                        { targetIds = [ "inv-1" ]
                        , targetSelectionSource = MigrationSelectedTargets MigrationInferredFromExactAmount
                        , strategy = OldestDueFirstThenOverpayOldest
                        }
                in
                Allocation.allocationIntentEncoder intent
                    |> Decode.decodeValue Allocation.allocationIntentDecoder
                    |> Expect.equal (Ok intent)
        ]
