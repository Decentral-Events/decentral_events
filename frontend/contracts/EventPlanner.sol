//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract EventPlanner {
    struct Event {
        string name;
        uint256 startTime;
        uint256 endTime;
        uint256 tokensRequired;
        uint256 validationRequired;
        uint256 maxBookings;
        uint256 totalBookings;
    }

    struct Booking {
        address user;
        uint256 eventId;
        uint256 totalValidators;
        bool attended;
        bool unstaked;
    }

    mapping(uint256 => Event) private events; // event id => event
    mapping(uint256 => mapping(address => uint256)) private bookingIds; // event id => user address => booking id
    mapping(uint256 => Booking) public bookings; // booking id => booking
    mapping(address => bool) public isAdmin; // user address => admin status
    mapping(uint256 => uint256) public tokensBlocked; // event id => blocked balance
    mapping(uint256 => mapping(address => bool)) public presenceMarked; // booking id => validator address => validation status

    uint256 public totalEvents;
    uint256 public totalBookings;
    address public tokenAddress;
    address public tresury;
    IERC20 tokenContract;

    event EventCreated(
        uint256 eventId,
        string name,
        uint256 startTime,
        uint256 endTime,
        uint256 tokensRequired,
        uint256 validationRequired,
        uint256 maxBookings
    );
    event AdminStatusChange(address user, bool status);
    event ReservationMade(
        uint256 eventId,
        uint256 bookingId,
        address user,
        uint256 totalBookings
    );
    event ReservationCancelled(
        uint256 eventId,
        uint256 bookingId,
        address user,
        uint256 totalBookings
    );
    event AttendanceMarked(uint256 eventId, uint256 bookingId, address user);
    event PresenceMarked(
        uint256 eventId,
        uint256 bookingId,
        address user,
        address validator,
        uint256 validationsRequired
    );
    event Unstaked(uint256 eventId, uint256 bookingId, address user);
    event Withdrawal(uint256 eventId, address admin);

    constructor(address _tokenAddress) {
        tokenAddress = _tokenAddress;
        tokenContract = IERC20(_tokenAddress);
        isAdmin[msg.sender] = true;
        emit AdminStatusChange(msg.sender, true);
    }

    modifier onlyAdmin() {
        require(isAdmin[msg.sender], "only admins allowed");
        _;
    }

    function changeAdminStatus(address user, bool status) public onlyAdmin {
        require(isAdmin[user] !== status, "status already updated");
        isAdmin[user] = status;
        emit AdminStatusChange(user, status);
    }

    function createEvent(
        string memory name,
        uint256 startTime,
        uint256 endTime,
        uint256 tokensRequired,
        uint256 validationRequired,
        uint256 maxBookings
    ) public onlyAdmin returns (uint256) {
        require(
            block.timestamp < startTime,
            "start time must be later than now"
        );
        require(startTime < endTime, "start time must be less than end time");
        uint256 eventId = totalEvents++;
        events[eventId] = Event(
            name,
            startTime,
            endTime,
            tokensRequired,
            validationRequired,
            maxBookings,
            0
        );
        emit EventCreated(
            eventId,
            name,
            startTime,
            endTime,
            tokensRequired,
            validationRequired,
            maxBookings
        );
        return eventId;
    }

    function bookTicket(uint256 eventId) public {
        Event memory currentEvent = getEvent(eventId);
        require(currentEvent.endTime > block.timestamp, "event already ended");
        require(
            currentEvent.startTime > block.timestamp,
            "event already started"
        );
        require(
            bookingIds[eventId][msg.sender] === 0,
            "you have already booked for this event"
        );
        require(
            currentEvent.totalBookings < currentEvent.maxBookings,
            "bookings limit has been reached"
        );
        uint256 userTokenAllowance = tokenContract.allowance(
            msg.sender,
            address(this)
        );
        require(
            currentEvent.tokensRequired <= userTokenAllowance,
            "insufficiant token allowance"
        );
        tokenContract.transferFrom(
            msg.sender,
            address(this),
            currentEvent.tokensRequired
        );
        tokensBlocked[eventId] += currentEvent.tokensRequired;
        uint256 bookingId = ++totalBookings;
        bookings[bookingId] = Booking(msg.sender, eventId, 0, false, false);
        bookingIds[eventId][msg.sender] = bookingId;
        events[eventId].totalBookings++;
        emit ReservationMade(
            eventId,
            bookingId,
            msg.sender,
            events[eventId].totalBookings
        );
    }

    function cancelBooking(uint256 eventId) public {
        Event memory currentEvent = getEvent(eventId);
        require(currentEvent.endTime > block.timestamp, "event already ended");
        require(
            currentEvent.startTime > block.timestamp,
            "event already started"
        );
        uint256 bookingId = getBookingId(eventId, msg.sender);
        if (!bookings[bookingId].attended) {
            tokensBlocked[eventId] -= currentEvent.tokensRequired;
        }
        delete bookings[bookingId];
        delete bookingIds[eventId][msg.sender];
        events[eventId].totalBookings--;
        tokenContract.transfer(msg.sender, events[eventId].tokensRequired);
        emit ReservationCancelled(
            eventId,
            bookingId,
            msg.sender,
            events[eventId].totalBookings
        );
    }

    function unstake(uint256 eventId) public {
        Event memory currentEvent = getEvent(eventId);
        require(currentEvent.endTime < block.timestamp, "event not over yet");
        uint256 bookingId = getBookingId(eventId, msg.sender);
        require(bookings[bookingId].attended, "you had not attended the event");
        require(!bookings[bookingId].unstaked, "you have already unstaked");
        bookings[bookingId].unstaked = true;
        tokenContract.transfer(msg.sender, events[eventId].tokensRequired);
        emit Unstaked(eventId, bookingId, msg.sender);
    }

    function markAttendance(uint256 eventId, address user) public onlyAdmin {
        Event memory currentEvent = getEvent(eventId);
        require(
            currentEvent.startTime < block.timestamp,
            "event not started yet"
        );
        require(currentEvent.endTime > block.timestamp, "event already ended");
        uint256 bookingId = getBookingId(eventId, user);
        require(
            !bookings[bookingId].attended,
            "the attendance is already marked"
        );
        bookings[bookingId].attended = true;
        tokensBlocked[eventId] -= currentEvent.tokensRequired;
        emit AttendanceMarked(eventId, bookingId, user);
    }

    function markPresence(uint256 eventId, address user) public {
        Event memory currentEvent = getEvent(eventId);
        require(
            currentEvent.startTime < block.timestamp,
            "event not started yet"
        );
        require(currentEvent.endTime > block.timestamp, "event already ended");
        uint256 bookingId = getBookingId(eventId, user);
        require(
            !bookings[bookingId].attended,
            "the attendance is already marked"
        );
        require(msg.sender !== user, "you cannot mark presence for yourself");
        require(
            bookingIds[eventId][msg.sender] !== 0,
            "you have not booked ticket for this event"
        );
        require(
            !presenceMarked[bookingId][msg.sender],
            "you have already marked presence"
        );
        presenceMarked[bookingId][msg.sender] = true;
        bookings[bookingId].totalValidators += 1;
        uint256 validationsRequired = currentEvent.validationRequired -
            bookings[bookingId].totalValidators;
        emit PresenceMarked(
            eventId,
            bookingId,
            user,
            msg.sender,
            validationsRequired
        );
        if (validationsRequired === 0) {
            bookings[bookingId].attended = true;
            emit AttendanceMarked(eventId, bookingId, user);
        }
    }

    function withdraw(uint256 eventId) public onlyAdmin {
        Event memory currentEvent = getEvent(eventId);
        require(currentEvent.endTime < block.timestamp, "event not ended yet");
        require(
            tokensBlocked[eventId] !== 0,
            "no tokens blocked for this event"
        );
        tokenContract.transfer(tresury, tokensBlocked[eventId]);
        tokensBlocked[eventId] = 0;
        emit Withdrawal(eventId, msg.sender);
    }

    function getEvent(uint256 eventId) public view returns (Event memory) {
        require(totalEvents > eventId, "event doesn't exist");
        return events[eventId];
    }

    function getBookingId(uint256 eventId, address user)
        public
        view
        returns (uint256)
    {
        uint256 bookingId = bookingIds[eventId][user];
        require(bookingId !== 0, "booking for this event not found");
        return bookingId;
    }
}
