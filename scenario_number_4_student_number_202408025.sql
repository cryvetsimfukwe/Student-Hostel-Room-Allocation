-- ============================================================================
-- 1. Create tables and insert sample data
-- ============================================================================

CREATE TABLE IF NOT EXISTS medicines (
    medicine_id SERIAL PRIMARY KEY,
    medicine_name VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE IF NOT EXISTS dispensing_records (
    record_id SERIAL PRIMARY KEY,
    medicine_id INT REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'DISPENSED' -- 'DISPENSED', 'REVERSED'
);

-- Add at least three medicines
INSERT INTO medicines (medicine_name, stock_quantity) VALUES
('Paracetamol 500mg', 50),
('Amoxicillin 250mg', 5),
('Ibuprofen 400mg', 0);


-- ============================================================================
-- 2. IF ELSIF ELSE block to report medicine stock level
-- ============================================================================

DO $$
DECLARE
    v_stock INT;
    v_med_name VARCHAR(100) := 'Amoxicillin 250mg';
BEGIN
    SELECT stock_quantity INTO v_stock 
    FROM medicines 
    WHERE medicine_name = v_med_name;

    IF v_stock = 0 THEN
        RAISE NOTICE 'Medicine "%" is OUT OF STOCK.', v_med_name;
    ELSIF v_stock <= 10 THEN
        RAISE NOTICE 'Medicine "%" is LOW ON STOCK (% remaining).', v_med_name, v_stock;
    ELSE
        RAISE NOTICE 'Medicine "%" is SUFFICIENTLY STOCKED (% remaining).', v_med_name, v_stock;
    END IF;
END $$;


-- ============================================================================
-- 3. WHILE loop (stock review days) & Numeric FOR loop (shelf inspections)
-- ============================================================================

DO $$
DECLARE
    v_day_count INT := 1;
BEGIN
    -- WHILE loop to show three stock review days
    RAISE NOTICE '--- Stock Review Days ---';
    WHILE v_day_count <= 3 LOOP
        RAISE NOTICE 'Stock Review Day %', v_day_count;
        v_day_count := v_day_count + 1;
    END LOOP;

    -- Numeric FOR loop to number three shelf inspections
    RAISE NOTICE '--- Shelf Inspections ---';
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Shelf Inspection #%', i;
    END LOOP;
END $$;


-- ============================================================================
-- 4. Procedure dispense_medicine
-- ============================================================================

CREATE OR REPLACE PROCEDURE dispense_medicine(
    p_medicine_id INT,
    p_student_number VARCHAR,
    p_quantity INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_stock INT;
BEGIN
    -- Validate quantity
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: %. Dispensing quantity must be positive.', p_quantity;
    END IF;

    -- Check stock quantity
    SELECT stock_quantity INTO v_current_stock
    FROM medicines
    WHERE medicine_id = p_medicine_id;

    IF v_current_stock IS NULL THEN
        RAISE NOTICE 'Medicine ID % does not exist.', p_medicine_id;
        RETURN;
    END IF;

    IF v_current_stock < p_quantity THEN
        RAISE NOTICE 'Cannot dispense % units of Medicine ID %. Only % in stock.', 
            p_quantity, p_medicine_id, v_current_stock;
        RETURN;
    END IF;

    -- Reduce stock quantity
    UPDATE medicines
    SET stock_quantity = stock_quantity - p_quantity
    WHERE medicine_id = p_medicine_id;

    -- Record dispensing action
    INSERT INTO dispensing_records (medicine_id, student_number, quantity, status)
    VALUES (p_medicine_id, p_student_number, p_quantity, 'DISPENSED');

    RAISE NOTICE 'Dispensed % units of Medicine ID % to Student %.', 
        p_quantity, p_medicine_id, p_student_number;
END;
$$;


-- ============================================================================
-- 5. Call dispense_medicine for 2 valid quantities and 1 exceeding stock
-- ============================================================================

-- Valid dispensing 1 (Medicine 1: Paracetamol, Qty 10)
CALL dispense_medicine(1, 'STU2001', 10);

-- Valid dispensing 2 (Medicine 2: Amoxicillin, Qty 3)
CALL dispense_medicine(2, 'STU2002', 3);

-- Dispensing request exceeding stock (Medicine 2 stock is now 2, requesting 5)
CALL dispense_medicine(2, 'STU2003', 5);

-- Query tables to inspect current state
SELECT * FROM medicines;
SELECT * FROM dispensing_records;


-- ============================================================================
-- 6. Procedure reverse_dispensing & double-call demonstration
-- ============================================================================

CREATE OR REPLACE PROCEDURE reverse_dispensing(
    p_record_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
    v_medicine_id INT;
    v_quantity INT;
BEGIN
    SELECT status, medicine_id, quantity 
    INTO v_status, v_medicine_id, v_quantity
    FROM dispensing_records
    WHERE record_id = p_record_id;

    IF v_status IS NULL THEN
        RAISE NOTICE 'Dispensing record ID % not found.', p_record_id;
        RETURN;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record ID % is already REVERSED. Stock will NOT be restored again.', p_record_id;
    ELSE
        -- Mark record as reversed
        UPDATE dispensing_records
        SET status = 'REVERSED'
        WHERE record_id = p_record_id;

        -- Restore stock quantity
        UPDATE medicines
        SET stock_quantity = stock_quantity + v_quantity
        WHERE medicine_id = v_medicine_id;

        RAISE NOTICE 'Dispensing Record ID % successfully reversed. Restored % units.', p_record_id, v_quantity;
    END IF;
END;
$$;

-- Call reverse_dispensing twice for Record ID 1
CALL reverse_dispensing(1);
CALL reverse_dispensing(1); -- Second call will skip stock restoration


-- ============================================================================
-- 7. Explicit cursor to display medicines below a low-stock threshold (<= 10)
-- ============================================================================

DO $$
DECLARE
    rec_med RECORD;
    v_threshold INT := 10;
    -- Explicit cursor definition
    cur_low_stock CURSOR FOR
        SELECT medicine_id, medicine_name, stock_quantity
        FROM medicines
        WHERE stock_quantity <= v_threshold;
BEGIN
    RAISE NOTICE '--- Medicines Below Low-Stock Threshold (<= %) ---', v_threshold;
    OPEN cur_low_stock;
    LOOP
        FETCH cur_low_stock INTO rec_med;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Medicine ID: %, Name: "%", Stock: %', 
            rec_med.medicine_id, rec_med.medicine_name, rec_med.stock_quantity;
    END LOOP;
    CLOSE cur_low_stock;
END $$;


-- ============================================================================
-- 8. Request a negative dispensing quantity and handle with EXCEPTION block
-- ============================================================================

DO $$
BEGIN
    CALL dispense_medicine(1, 'STU2004', -5);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Caught Exception: %', SQLERRM;
END $$;


-- ============================================================================
-- 9. Final Verification Queries
-- ============================================================================

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;