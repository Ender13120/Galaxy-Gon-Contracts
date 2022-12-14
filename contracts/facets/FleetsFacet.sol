// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AppStorage, Modifiers, CraftItem, SendCargo, SendTerraform, attackStatus} from "../libraries/AppStorage.sol";
import "../interfaces/IPlanets.sol";
import "../interfaces/IFleets.sol";

import "../interfaces/IShips.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IResource.sol";

contract FleetsFacet is Modifiers {
    function craftFleet(uint256 _fleetId, uint256 _planetId)
        external
        onlyPlanetOwner(_planetId)
    {
        IFleets fleetsContract = IFleets(s.fleets);
        uint256[3] memory price = fleetsContract.getPrice(_fleetId);
        uint256 craftTime = fleetsContract.getCraftTime(_fleetId);
        uint256 craftedFrom = fleetsContract.getCraftedFrom(_fleetId);
        uint256 buildings = IPlanets(s.planets).getBuildings(
            _planetId,
            craftedFrom
        );
        require(craftTime > 0, "FleetsFacet: not released yet");
        require(
            s.craftFleets[_planetId].itemId == 0,
            "FleetsFacet: planet already crafting"
        );
        require(buildings > 0, "FleetsFacet: missing building requirement");
        uint256 readyTimestamp = block.timestamp + craftTime;
        CraftItem memory newFleet = CraftItem(_fleetId, readyTimestamp);
        s.craftFleets[_planetId] = newFleet;
        IERC20(s.metal).burnFrom(msg.sender, price[0]);
        IERC20(s.crystal).burnFrom(msg.sender, price[1]);
        IERC20(s.ethereus).burnFrom(msg.sender, price[2]);
    }

    function claimFleet(uint256 _planetId) external onlyPlanetOwner(_planetId) {
        require(
            block.timestamp >= s.craftFleets[_planetId].readyTimestamp,
            "FleetsFacet: not ready yet"
        );
        uint256 shipId = IShips(s.ships).mint(
            msg.sender,
            s.craftFleets[_planetId].itemId
        );
        uint256 fleetId = s.craftFleets[_planetId].itemId;
        delete s.craftFleets[_planetId];

        IPlanets(s.planets).addFleet(_planetId, fleetId, shipId);
        IShips(s.ships).assignShipToPlanet(shipId, _planetId);
    }

    function sendCargo(
        uint256 _fromPlanetId,
        uint256 _toPlanetId,
        uint256 _fleetId,
        uint256 _resourceId
    ) external onlyPlanetOwner(_fromPlanetId) {
        //todo: require only cargo ships
        SendCargo memory newSendCargo = SendCargo(
            _fromPlanetId,
            _toPlanetId,
            _fleetId,
            _resourceId,
            block.timestamp
        );
        s.sendCargoId++;
        s.sendCargo[s.sendCargoId] = newSendCargo;
        // emit event
    }

    function returnCargo(uint256 _sendCargoId) external {
        require(
            msg.sender ==
                IERC721(s.planets).ownerOf(
                    s.sendCargo[_sendCargoId].fromPlanetId
                ),
            "AppStorage: Not owner"
        );
        (uint256 fromX, uint256 fromY) = IPlanets(s.planets).getCoordinates(
            s.sendCargo[_sendCargoId].fromPlanetId
        );
        (uint256 toX, uint256 toY) = IPlanets(s.planets).getCoordinates(
            s.sendCargo[_sendCargoId].toPlanetId
        );
        uint256 xDist = fromX > toX ? fromX - toX : toX - fromX;
        uint256 yDist = fromY > toY ? fromY - toY : toY - fromY;
        uint256 distance = xDist + yDist;
        require(
            block.timestamp >=
                s.sendCargo[_sendCargoId].timestamp + (distance * 2),
            "FleetsFacet: not ready yet"
        );
        uint256 cargo = IFleets(s.fleets).getCargo(
            s.sendCargo[_sendCargoId].fleetId
        );
        IPlanets(s.planets).mineResource(
            s.sendCargo[_sendCargoId].toPlanetId,
            s.sendCargo[_sendCargoId].resourceId,
            cargo
        );
        IResource(s.ethereus).mint(msg.sender, cargo);
        delete s.sendCargo[_sendCargoId];
    }

    function sendTerraform(
        uint256 _fromPlanetId,
        uint256 _toPlanetId,
        uint256 _fleetId
    ) external onlyPlanetOwner(_fromPlanetId) {
        //todo: require only to empty planet
        //todo: only terraform ship
        SendTerraform memory newSendTerraform = SendTerraform(
            _fromPlanetId,
            _toPlanetId,
            _fleetId,
            block.timestamp
        );
        s.sendTerraformId++;
        s.sendTerraform[s.sendTerraformId] = newSendTerraform;
        // emit event
    }

    function endTerraform(uint256 _sendTerraformId) external {
        require(
            msg.sender ==
                IERC721(s.planets).ownerOf(
                    s.sendTerraform[_sendTerraformId].fromPlanetId
                ),
            "AppStorage: Not owner"
        );
        (uint256 fromX, uint256 fromY) = IPlanets(s.planets).getCoordinates(
            s.sendTerraform[_sendTerraformId].fromPlanetId
        );
        (uint256 toX, uint256 toY) = IPlanets(s.planets).getCoordinates(
            s.sendTerraform[_sendTerraformId].toPlanetId
        );
        uint256 xDist = fromX > toX ? fromX - toX : toX - fromX;
        uint256 yDist = fromY > toY ? fromY - toY : toY - fromY;
        uint256 distance = xDist + yDist;
        require(
            block.timestamp >=
                s.sendTerraform[_sendTerraformId].timestamp + distance,
            "FleetsFacet: not ready yet"
        );
        //todo: conquer planet
    }

    function getCraftFleets(uint256 _planetId)
        external
        view
        returns (uint256, uint256)
    {
        return (
            s.craftFleets[_planetId].itemId,
            s.craftFleets[_planetId].readyTimestamp
        );
    }

    function sendAttack(
        uint256 _fromPlanetId,
        uint256 _toPlanetId,
        uint256[] memory _shipIds //tokenId's of ships to send
    ) external onlyPlanetOwner(_fromPlanetId) {
        require(
            msg.sender != IERC721(s.planets).ownerOf(_toPlanetId),
            "you cannot attack your own planets!"
        );


        //check if ships are assigned to the planet
        for (uint i = 0; i < _shipIds.length; i++) {
            require(
                IShips(s.ships).checkAssignedPlanet([_shipIds[i]) == _fromPlanetId,
                "ship is not assigned to this planet!"
            );

            //unassign ships during attack
            IShips(s.ships).deleteShipFromPlanet(_shipIds[i]);

            //@TODO remove from defense array..fml
        }

        //refactor to  an internal func

        (uint256 fromX, uint256 fromY) = IPlanets(s.planets).getCoordinates(
            _fromPlanetId
        );
        (uint256 toX, uint256 toY) = IPlanets(s.planets).getCoordinates(
            _toPlanetId
        );

        uint256 xDist = fromX > toX ? fromX - toX : toX - fromX;
        uint256 yDist = fromY > toY ? fromY - toY : toY - fromY;
        uint256 distance = xDist + yDist;

        attackStatus memory attackToBeAdded;

        attackToBeAdded.attackStarted = block.timestamp;

        attackToBeAdded.distance = distance;

        attackToBeAdded.timeToBeResolved = block.timestamp + distance + 120; // minimum 2min test

        attackToBeAdded.fromPlanet = _fromPlanetId;

        attackToBeAdded.toPlanet = _toPlanetId;

        attackToBeAdded.attackerShipsIds = _shipIds;

        attackToBeAdded.attacker = msg.sender;

        IPlanets(s.planets).addAttack(attackToBeAdded);

        //@TODO

        // attacker ships are unassigned from shipId => PlanetId Mapping( to prevent them being used until this attack is resolved)

        // calculate resolvement time
    }

    function sendFriendlies(uint256 _fromPlanetId, uint256 _toPlanetId)
        external
        onlyPlanetOwner(_fromPlanetId)
        onlyPlanetOwner(_toPlanetId)
    {}

    function resolveAttack(uint _attackInstanceId) external {
        attackStatus memory attackToResolve = IPlanets(s.planets).getAttack(
            _attackInstanceId
        );

        require(
            block.timestamp >= attackToResolve.timeToBeResolved,
            "attack fleet hasnt arrived yet!"
        );

        uint[] memory attackerShips = attackToResolve.attackerShipsId;
        uint[] memory defenderShips = IPlanets(s.planets).getDefensePlanet(
            attackToResolve.toPlanet
        );

        int attackStrength;
        int attackHealth;

        int defenseStrength;
        int defenseHealth;
        for (uint i = 0; i < attackerShips.length; i++) {
            attackStrength += IShips(s.ships)
                .getShipStats(attackerShips[i])
                .attack;
            attackHealth += IShips(s.ships)
                .getShipStats(attackerShips[i])
                .health;
        }

        for (uint i = 0; i < defenderShips.length; i++) {
            defenseStrength += IShips(s.ships)
                .getShipStats(defenderShips[i])
                .attack;

            defenseHealth += IShips(s.ships)
                .getShipStats(defenderShips[i])
                .health;
        }

        //to be improved later, very rudimentary resolvement
        // 100 - 50 = 50 dmg
        int battleResult = attackStrength - defenseStrength;

        //attacker has higher atk than defender
        if (battleResult > 0) {
            //attacker has higher atk than defender + entire health destroyed
            //win for attacker
            if (battleResult >= defenseHealth) {
                //burn defender ships

                //burn NFTs
                //remove  shipID assignment to Planet

                for (uint i = 0; i < defenderShips.length; i++) {
                    IShips(s.ships).burnShip(defenderShips[i]);
                    IShips(s.ships).deleteShipFromPlanet(defenderShips[i]);
                }

                //conquer planet
                //give new owner the planet
                address loserAddr = IERC721(s.planets).ownerOf(
                    attackToResolve.toPlanet
                );

                IPlanets(s.planets).planetConquestTransfer(
                    attackToResolve.toPlanet,
                    loserAddr,
                    attackToResolve.attacker
                );

                //damage to attackerForce, random? @TODO

                //assign attacker fleet to planet defender array
                IPlanets(s.planets).assignDefensePlanet(attackToResolve.toPlanet,attackerShips);
                    

                //assign attacker ships to new planet
                for (uint i = 0; i < attackerShips.length; i++) {
                    IShips(s.ships).assignShipToPlanet(
                        attackerShips[i],attackToResolve.toPlanet
                    );
                }
            }


            //burn killed ships until there are no more left; then reassign attacking fleet to home-planet
            else {

                //burn nfts and unassign ship from planets, also reduce defenderShip Array
                for (uint i = 0; i < defenderShips.length; i++) {

                    uint defenderShipHealth = IShips(s.ships).getShipStats(defenderShips[i]).health;

                    if (
                        battleResult >
                            defenderShipHealth
                    ) {
                        battleResult -= defenderShipHealth;


                        IShips(s.ships).burnShip(defenderShips[i]);
                        IShips(s.ships).deleteShipFromPlanet(
                            [defenderShips[i]]
                        );
                        delete defenderShip[i];

                        

                    }
                }

                //update planet defense array mapping
                 IPlanets(s.planets).assignDefensePlanet(attackToResolve.toPlanet,defenderShip);



                //@TODO send attacker ships back to home-planet.
                

        

            }





        }

        //defender has higher atk than attacker
        if (battleResult < 0) {}

        //draw
        if (battleResult == 0) {}
    }
}
