/**                                                                              
                                            ..                                  
                                          ,*.                                   
                                        .**,                                    
                                       ,***.                                    
                                 .,.   ,***,                                    
                               .**,    *****.                                   
                             .****.    ,*****,                                  
                           .******,     ,******,                                
                         .*******.       .********,              .              
                       ,******.            .*************,,*****.               
                     ,*****.        ,,.        ,************,.                  
                  .,****.         ,*****,                                       
                 ,***,          ,*******,.              ..                      
               ,**,          .*******,.       ,********.                        
                           .******,.       .********,                           
                         .*****,         .*******,                              
                       ,****,          .******,                                 
                     ,***,.          .*****,                                    
                   ,**,.           ./***,                                       
                  ,,             .***,                                          
                               .**,                                 
            __  _______  ____  _   _______ __  ______  ______         
           /  |/  / __ \/ __ \/ | / / ___// / / / __ \/_  __/         
          / /|_/ / / / / / / /  |/ /\__ \/ /_/ / / / / / /            
         / /  / / /_/ / /_/ / /|  /___/ / __  / /_/ / / /             
        /_/  /_/\____/\____/_/_|_//____/_/_/_/\____/_/_/__    ________
          / ____/ __ \/ /   / /   / ____/ ____/_  __/  _/ |  / / ____/
         / /   / / / / /   / /   / __/ / /     / /  / / | | / / __/   
        / /___/ /_/ / /___/ /___/ /___/ /___  / / _/ /  | |/ / /___   
        \____/\____/_____/_____/_____/\____/ /_/ /___/  |___/_____/                                                           
*/

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Diplomacy is AccessControl, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /**
    @notice Election Definition 
    */
    struct Election {
        string name;                            // Creator title/names/etc
        bool active;                            // Election status
        bool paid;                              // Election payout status
        uint256 createdAt;                      // Creation block time-stamp
        address[] candidates;                   // Candidates (who can vote/be voted)
        uint256 funds;                          // Allowance of ETH or Tokens for Election
        address token;                          // Address of Election Token (Eth -> 0x00..)
        uint256 votes;                          // Number of votes delegated to each candidate
        address admin;                          // Address of Election Admin
        // mapping(address => bool) voted;         // Voter status // --> move all mappings to outside of struct 
        // mapping(address => string[]) scores;    // string of sqrt votes
    }
    
    mapping(uint256 => mapping(address => bool)) public voted;
    mapping(uint256 => mapping(address => string[])) public scores;

    mapping(uint256 => Election) public elections;
    
    constructor() ReentrancyGuard() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    event BallotCast(address voter, uint256 electionId, address[] adrs, string[] scores);
    event ElectionCreated(address creator, uint256 electionId);
    event ElectionEnded(uint256 electionId);
    event ElectionPaid(uint256 electionId);

    bytes32 internal constant ELECTION_ADMIN_ROLE =
        keccak256("ELECTION_ADMIN_ROLE");
    bytes32 internal constant ELECTION_CANDIDATE_ROLE =
        keccak256("ELECTION_CANDIDATE_ROLE");

    modifier onlyContractAdmin() {

        require( hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Sender not Contract Admin!" );
        _;

    }

    modifier onlyElectionCandidate(uint256 electionId) {

        require( hasRole(ELECTION_CANDIDATE_ROLE, msg.sender), "Sender not Election Candidate!" );
        require( isElectionCandidate(electionId, msg.sender), "Sender not Election Candidate!" );
        _;

    }

    modifier onlyElectionAdmin(uint256 electionId) {

        require( hasRole(ELECTION_ADMIN_ROLE, msg.sender), "Sender not Election Admin!" );
        require( msg.sender == elections[electionId].admin, "Sender not Election Admin!" );
        _;

    }

    modifier validBallot(
        uint256 electionId,
        address[] memory _adrs,
        string[] memory _scores
    ) {

        require( elections[electionId].active, "Election Not Active!" );
        require( !voted[electionId][msg.sender], "Sender already voted!" );
        require ( _scores.length == _adrs.length, "Scores - Address Mismatch!" );
        //require ( _scores.length == elections[electionId].votes, "Not enough votes sent!" );
        _;

    }

    uint256 public numElections;

    /**
    @notice New Ethereum Reward Election
    */
    function _newEthElection(
        string memory _name,
        uint256 _funds,
        uint256 _votes,
        address[] memory _adrs
    ) internal returns (uint256 electionId) {
        
        electionId = numElections++; // why does .add break it?
        Election storage election = elections[electionId];
        election.name = _name;
        election.funds = _funds;
        election.votes = _votes;
        election.candidates = _adrs;
        election.createdAt = block.timestamp;
        election.active = true;
        election.admin = msg.sender;

    }

    /**
    @notice New Token Reward Election
    */
    function _newTokenElection(
        string memory _name,
        uint256 _funds,
        address _token,
        uint256 _votes,
        address[] memory _adrs
    ) internal returns (uint256 electionId) {

        electionId = numElections++;
        Election storage election = elections[electionId];
        election.name = _name;
        election.funds = _funds;
        election.token = _token;
        election.votes = _votes;
        election.candidates = _adrs;
        election.createdAt = block.timestamp;
        election.active = true;
        election.admin = msg.sender;

    }

   /**
    @notice Create a new election  
    */
    function newElection(
        string memory _name,
        uint256 _funds,
        address _token,
        uint256 _votes,
        address[] memory _adrs
    ) public returns (uint256 electionId) {

        if ( _token == address(0) ) { // 0x00.. --> Eth Election
            electionId = _newEthElection(_name, _funds, _votes, _adrs);
        } else { // Token Election
            electionId = _newTokenElection(_name, _funds, _token, _votes, _adrs);
        }
        // Setup roles
        setElectionCandidateRoles(_adrs);
        setElectionAdminRole(msg.sender);
        emit ElectionCreated(msg.sender, electionId);

    }

    /**
    @notice Cast a ballot to an election
    */
    function castBallot(
        uint256 electionId,
        address[] memory _adrs,
        string[] memory _scores // submitted sqrt of votes
    ) public onlyElectionCandidate(electionId) 
        validBallot(electionId, _adrs, _scores) {

        for (uint256 i = 0; i < _adrs.length; i++) {
            scores[electionId][_adrs[i]].push(_scores[i]); 
        }
        voted[electionId][msg.sender] = true;
        emit BallotCast(msg.sender, electionId, _adrs, _scores);

    }

    /**
    @notice End an Active Election
    */
    function endElection(uint256 electionId) 
    public onlyElectionAdmin(electionId) {

        Election storage election = elections[electionId];
        require( election.active, "Election Already Ended!" );
        election.active = false;
        emit ElectionEnded(electionId); // look into diff methods 

    }

    /**
    @notice Payout the election with ETH 
    */
    function _ethPayout(
        uint256 electionId, 
        address[] memory _adrs, 
        uint256[] memory _pay
    ) internal onlyElectionAdmin(electionId) returns(bool) {

        uint256 paySum;
        // bool status;
        for (uint256 i = 0; i < elections[electionId].candidates.length; i++) {
            require( elections[electionId].candidates[i] == _adrs[i], "Election-Address Mismatch!" );
            paySum += _pay[i];
        }
        for (uint256 i = 0; i < _pay.length; i++) {
            // Call returns a boolean value indicating success or failure.
            (bool sent, bytes memory data) = _adrs[i].call{value: _pay[i]}("");
            require(sent, "Failed to send Ether");
        }
        
        return true; 

    }

    /**
    @notice Payout the election with the selected token  
    */
    function _tokenPayout(
        uint256 electionId, 
        address[] memory _adrs, 
        uint256[] memory _pay
    ) internal returns(bool) {

        // Distribute tokens to each candidate
        for (uint256 i = 0; i < elections[electionId].candidates.length; i++) {
            IERC20(elections[electionId].token).safeTransferFrom(msg.sender, _adrs[i], _pay[i]); // omit
        }
        return true;

    }

    /**
    @notice User Approve selected token for the Funding Amount
    */
    function approveToken(uint256 electionId) public {
        // Safe approve?
        IERC20(elections[electionId].token).approve(address(this), elections[electionId].funds);
    }

    /**
    @notice Payout the election
    */
    function payoutElection(
        uint256 electionId,
        address[] memory _adrs,
        uint256[] memory _pay
    ) public payable onlyElectionAdmin(electionId) nonReentrant() {

        require( !elections[electionId].active, "Election Still Active!" );
        bool status;
        if ( elections[electionId].token == address(0) ) {
            status = _ethPayout(electionId, _adrs, _pay);
        } else {
            status = _tokenPayout(electionId, _adrs, _pay);
        }
		elections[electionId].paid = status;
        emit ElectionPaid(electionId);

    }

    // Setters
    function setElectionCandidateRoles(address[] memory _adrs) internal {

        for (uint256 i = 0; i < _adrs.length; i++) {
            _setupRole(ELECTION_CANDIDATE_ROLE, _adrs[i]);
        }

    }

    function setElectionAdminRole(address adr) internal {
        _setupRole(ELECTION_ADMIN_ROLE, adr);
    }

    /**
    @notice Get election metadata by the ID  
    */ 
    // Use a struct mapping instead! 
    function getElectionById(uint256 electionId)
    public view 
    returns (
        string memory name,
        address[] memory candidates,
        uint256 n_addr,
        uint256 createdAt,
        uint256 funds,
        address token,
        uint256 votes,
        address admin,
        bool isActive,
        bool paid
    ) {

        name = elections[electionId].name;
        candidates = elections[electionId].candidates;
        n_addr = elections[electionId].candidates.length;
        createdAt = elections[electionId].createdAt;
        funds = elections[electionId].funds;
        token = elections[electionId].token;
        votes = elections[electionId].votes;
        admin = elections[electionId].admin;
        isActive = elections[electionId].active;
        paid = elections[electionId].paid;

    }

    function getElectionScores(uint256 electionId, address _adr) 
    public view returns (string[] memory) {
        return scores[electionId][_adr];
    }

    function getElectionVoted(uint256 electionId) 
    public view returns (uint256 count) {

        for (uint256 i = 0; i < elections[electionId].candidates.length; i++) {
            address candidate = elections[electionId].candidates[i];
            if (voted[electionId][candidate]) {
                count++;
            }
        }

    }

    function canVote(uint256 electionId, address _sender)
    public view returns (bool status) { // Redundant w/ isElectionCandidate?

        for (uint256 i = 0; i < elections[electionId].candidates.length; i++) {
            address candidate = elections[electionId].candidates[i];
            if (_sender == candidate) {
                status = true;
            }
        }

    }

    function isElectionAdmin(uint256 electionId, address _sender) 
    public view returns (bool) {
        return _sender == elections[electionId].admin;
    }

    function isElectionCandidate(uint256 electionId, address _sender) 
    public view returns (bool status) {

        for (uint256 i = 0; i < elections[electionId].candidates.length; i++) {
            if (_sender == elections[electionId].candidates[i]) {
                status = true;
                break;
            }
        }

    }

    function hasVoted(uint256 electionId, address _sender) 
    public view returns (bool) {
        return voted[electionId][_sender];
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}

}
