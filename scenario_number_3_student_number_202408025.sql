-- ============================================================================
-- 1. Create tables and insert sample rooms
-- ============================================================================
CREATE TABLE hostel_rooms (
    room_id SERIAL PRIMARY KEY,
    room_number VARCHAR(10) UNIQUE NOT NULL,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id INT REFERENCES hostel_rooms(room_id),
    status VARCHAR(20) NOT NULL DEFAULT 'ALLOCATED'
);

-- Add at least three rooms
INSERT INTO hostel_rooms (room_number, available_spaces) VALUES
('Room 101', 2),
('Room 102', 1),
('Room 103', 0);


-- ============================================================================
-- 2. IF ELSIF ELSE to report room availability status
-- ============================================================================
DO $$
DECLARE
    r RECORD;
BEGIN
    RAISE NOTICE '--- ROOM STATUS REPORT ---';
    FOR r IN SELECT room_number, available_spaces FROM hostel_rooms LOOP
        IF r.available_spaces = 0 THEN
            RAISE NOTICE '% is FULL.', r.room_number;
        ELSIF r.available_spaces = 1 THEN
            RAISE NOTICE '% has ONE space left.', r.room_number;
        ELSE
            RAISE NOTICE '% has SEVERAL spaces left (%).', r.room_number, r.available_spaces;
        END IF;
    END LOOP;
END $$;


-- ============================================================================
-- 3. WHILE loop for inspection days and numeric FOR loop for room checks
-- ============================================================================
DO $$
DECLARE
    day_count INT := 1;
    check_num INT;
BEGIN
    RAISE NOTICE '--- HOSTEL INSPECTION LOG ---';
    WHILE day_count <= 3 LOOP
        RAISE NOTICE 'Inspection Day %:', day_count;
        
        FOR check_num IN 1..3 LOOP
            RAISE NOTICE '   Room Check % completed.', check_num;
        END LOOP; -- <--- Corrected here (was END FOR;)
        
        day_count := day_count + 1;
    END LOOP; -- <--- Closes the WHILE loop
END $$;

-- ============================================================================
-- 4. Create allocate_room procedure
-- ============================================================================
CREATE OR REPLACE PROCEDURE allocate_room(
    p_student_number VARCHAR,
    p_room_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    -- Check for blank/null student number (for task 8 handling)
    IF p_student_number IS NULL OR TRIM(p_student_number) = '' THEN
        RAISE EXCEPTION 'Student number cannot be blank or empty.';
    END IF;

    -- Get current availability
    SELECT available_spaces INTO v_available
    FROM hostel_rooms
    WHERE room_id = p_room_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Error: Room ID % does not exist.', p_room_id;
        RETURN;
    END IF;

    -- Check if space is available
    IF v_available > 0 THEN
        -- Reduce availability by one
        UPDATE hostel_rooms
        SET available_spaces = available_spaces - 1
        WHERE room_id = p_room_id;

        -- Record the student allocation
        INSERT INTO allocations (student_number, room_id, status)
        VALUES (p_student_number, p_room_id, 'ALLOCATED');

        RAISE NOTICE 'Successfully allocated Student % to Room ID %.', p_student_number, p_room_id;
    ELSE
        RAISE NOTICE 'Allocation failed: Room ID % is FULL.', p_room_id;
    END IF;
END $$;


-- ============================================================================
-- 5. Call allocate_room for 2 valid allocations and 1 full room allocation
-- ============================================================================
-- Valid allocation 1 (Room 101)
CALL allocate_room('STD001', 1);

-- Valid allocation 2 (Room 102)
CALL allocate_room('STD002', 2);

-- Attempt allocation to a full room (Room 103 has 0 spaces)
CALL allocate_room('STD003', 3);

-- Query rooms and allocations
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;


-- ============================================================================
-- 6. Create check_out procedure (handles multiple calls safely)
-- ============================================================================
CREATE OR REPLACE PROCEDURE check_out(
    p_allocation_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
    v_room_id INT;
BEGIN
    -- Fetch current status and room ID
    SELECT status, room_id INTO v_status, v_room_id
    FROM allocations
    WHERE allocation_id = p_allocation_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Error: Allocation ID % not found.', p_allocation_id;
        RETURN;
    END IF;

    -- Ensure space is freed only if the allocation is active
    IF v_status = 'ALLOCATED' THEN
        -- Mark allocation complete
        UPDATE allocations
        SET status = 'CHECKED_OUT'
        WHERE allocation_id = p_allocation_id;

        -- Release a bed space
        UPDATE hostel_rooms
        SET available_spaces = available_spaces + 1
        WHERE room_id = v_room_id;

        RAISE NOTICE 'Allocation ID % successfully checked out. Space released.', p_allocation_id;
    ELSE
        RAISE NOTICE 'Allocation ID % is already %. No space was freed.', p_allocation_id, v_status;
    END IF;
END $$;

-- Call check_out twice for the same allocation (e.g., Allocation ID 1)
CALL check_out(1);
CALL check_out(1); -- Second call will not free another space


-- ============================================================================
-- 7. Explicit cursor to display full or nearly full rooms (0 or 1 space)
-- ============================================================================
DO $$
DECLARE
    cur_full_rooms CURSOR FOR 
        SELECT room_number, available_spaces 
        FROM hostel_rooms 
        WHERE available_spaces <= 1;
        
    v_room_number VARCHAR(10);
    v_spaces INT;
BEGIN
    RAISE NOTICE '--- FULL OR NEARLY FULL ROOMS ---';
    OPEN cur_full_rooms;
    LOOP
        FETCH cur_full_rooms INTO v_room_number, v_spaces;
        EXIT WHEN NOT FOUND;
        
        IF v_spaces = 0 THEN
            RAISE NOTICE 'Room % is FULL.', v_room_number;
        ELSE
            RAISE NOTICE 'Room % is NEARLY FULL (% space left).', v_room_number, v_spaces;
        END IF;
    END LOOP;
    CLOSE cur_full_rooms;
END $$;


-- ============================================================================
-- 8. Attempt allocation with a blank student number & EXCEPTION block
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '--- TESTING INVALID ALLOCATION INPUT ---';
    CALL allocate_room('   ', 1);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'EXCEPTION CAUGHT: %', SQLERRM;
END $$;


-- ============================================================================
-- 9. Query both tables to show final states
-- ============================================================================
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
