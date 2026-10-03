-- ============================================================================
-- 1. Create tables and insert sample data
-- ============================================================================

CREATE TABLE IF NOT EXISTS events (
    event_id SERIAL PRIMARY KEY,
    event_name VARCHAR(100) NOT NULL,
    available_seats INT NOT NULL CHECK (available_seats >= 0)
);

CREATE TABLE IF NOT EXISTS bookings (
    booking_id SERIAL PRIMARY KEY,
    event_id INT REFERENCES events(event_id),
    student_number VARCHAR(20) NOT NULL,
    number_of_seats INT NOT NULL CHECK (number_of_seats > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'BOOKED' -- 'BOOKED', 'CANCELLED'
);

-- Add at least three events
INSERT INTO events (event_name, available_seats) VALUES
('Annual Hackathon', 50),
('Career Fair', 3),
('AI Guest Lecture', 0);


-- ============================================================================
-- 2. IF ELSIF ELSE block to report seat availability
-- ============================================================================

DO $$
DECLARE
    v_seats INT;
    v_event_name VARCHAR(100) := 'Career Fair';
BEGIN
    SELECT available_seats INTO v_seats 
    FROM events 
    WHERE event_name = v_event_name;

    IF v_seats = 0 THEN
        RAISE NOTICE 'Event "%" is FULL.', v_event_name;
    ELSIF v_seats <= 5 THEN
        RAISE NOTICE 'Event "%" is NEARLY FULL (% seats left).', v_event_name, v_seats;
    ELSE
        RAISE NOTICE 'Event "%" HAS PLENTY OF SEATS (% seats left).', v_event_name, v_seats;
    END IF;
END $$;


-- ============================================================================
-- 3. WHILE loop (booking reminder days) & Numeric FOR loop (entrance checks)
-- ============================================================================

DO $$
DECLARE
    v_reminder_day INT := 1;
BEGIN
    -- WHILE loop to display three booking reminder days
    RAISE NOTICE '--- Booking Reminder Days ---';
    WHILE v_reminder_day <= 3 LOOP
        RAISE NOTICE 'Booking Reminder Day %', v_reminder_day;
        v_reminder_day := v_reminder_day + 1;
    END LOOP;

    -- Numeric FOR loop to number three entrance checks
    RAISE NOTICE '--- Entrance Checks ---';
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Entrance Check #%', i;
    END LOOP;
END $$;


-- ============================================================================
-- 4. Procedure book_seats
-- ============================================================================

CREATE OR REPLACE PROCEDURE book_seats(
    p_event_id INT,
    p_student_number VARCHAR,
    p_number_of_seats INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_seats INT;
BEGIN
    -- Validate requested seat count
    IF p_number_of_seats <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: %. Seat quantity must be greater than zero.', p_number_of_seats;
    END IF;

    -- Check availability
    SELECT available_seats INTO v_current_seats
    FROM events
    WHERE event_id = p_event_id;

    IF v_current_seats IS NULL THEN
        RAISE NOTICE 'Event ID % does not exist.', p_event_id;
        RETURN;
    END IF;

    IF v_current_seats < p_number_of_seats THEN
        RAISE NOTICE 'Cannot book % seats for Event ID %. Only % seats available.', 
            p_number_of_seats, p_event_id, v_current_seats;
        RETURN;
    END IF;

    -- Reduce available seats
    UPDATE events
    SET available_seats = available_seats - p_number_of_seats
    WHERE event_id = p_event_id;

    -- Record booking
    INSERT INTO bookings (event_id, student_number, number_of_seats, status)
    VALUES (p_event_id, p_student_number, p_number_of_seats, 'BOOKED');

    RAISE NOTICE 'Booked % seats for Event ID % by Student %.', 
        p_number_of_seats, p_event_id, p_student_number;
END;
$$;


-- ============================================================================
-- 5. Call book_seats for 2 valid bookings and 1 request exceeding available seats
-- ============================================================================

-- Valid booking 1 (Event 1: Annual Hackathon, 2 seats)
CALL book_seats(1, 'STU3001', 2);

-- Valid booking 2 (Event 2: Career Fair, 2 seats)
CALL book_seats(2, 'STU3002', 2);

-- Request exceeding remaining seats (Event 2 now has 1 seat left, requesting 2)
CALL book_seats(2, 'STU3003', 2);

-- Query events and bookings to inspect current state
SELECT * FROM events;
SELECT * FROM bookings;


-- ============================================================================
-- 6. Procedure cancel_booking & double-call demonstration
-- ============================================================================

CREATE OR REPLACE PROCEDURE cancel_booking(
    p_booking_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
    v_event_id INT;
    v_seats INT;
BEGIN
    SELECT status, event_id, number_of_seats 
    INTO v_status, v_event_id, v_seats
    FROM bookings
    WHERE booking_id = p_booking_id;

    IF v_status IS NULL THEN
        RAISE NOTICE 'Booking ID % not found.', p_booking_id;
        RETURN;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Booking ID % is already CANCELLED. Seats will NOT be released again.', p_booking_id;
    ELSE
        -- Mark booking as cancelled
        UPDATE bookings
        SET status = 'CANCELLED'
        WHERE booking_id = p_booking_id;

        -- Release seats
        UPDATE events
        SET available_seats = available_seats + v_seats
        WHERE event_id = v_event_id;

        RAISE NOTICE 'Booking ID % successfully cancelled. Released % seats.', p_booking_id, v_seats;
    END IF;
END;
$$;

-- Call cancel_booking twice for Booking ID 1
CALL cancel_booking(1);
CALL cancel_booking(1); -- Second call will skip releasing seats again


-- ============================================================================
-- 7. Explicit cursor to display full or nearly full events (<= 5 seats)
-- ============================================================================

DO $$
DECLARE
    rec_event RECORD;
    v_threshold INT := 5;
    -- Explicit cursor definition
    cur_limited_seats CURSOR FOR
        SELECT event_id, event_name, available_seats
        FROM events
        WHERE available_seats <= v_threshold;
BEGIN
    RAISE NOTICE '--- Full or Nearly Full Events (<= % seats left) ---', v_threshold;
    OPEN cur_limited_seats;
    LOOP
        FETCH cur_limited_seats INTO rec_event;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Event ID: %, Name: "%", Available Seats: %', 
            rec_event.event_id, rec_event.event_name, rec_event.available_seats;
    END LOOP;
    CLOSE cur_limited_seats;
END $$;


-- ============================================================================
-- 8. Try to book zero seats and handle with EXCEPTION block
-- ============================================================================

DO $$
BEGIN
    CALL book_seats(1, 'STU3004', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Caught Exception: %', SQLERRM;
END $$;


-- ============================================================================
-- 9. Final Verification Queries
-- ============================================================================

SELECT * FROM events ORDER BY event_id;
SELECT * FROM bookings ORDER BY booking_id;