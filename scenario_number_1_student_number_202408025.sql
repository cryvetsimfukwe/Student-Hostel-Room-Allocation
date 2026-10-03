-- ============================================================================
-- 1. Create tables and insert sample data
-- ============================================================================

CREATE TABLE IF NOT EXISTS books (
    book_id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE IF NOT EXISTS book_loans (
    loan_id SERIAL PRIMARY KEY,
    book_id INT REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    loan_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' -- 'ACTIVE', 'RETURNED'
);

-- Insert at least three books
INSERT INTO books (title, available_copies) VALUES
('Database Systems', 5),
('Introduction to Algorithms', 1),
('Clean Code', 0);


-- ============================================================================
-- 2. IF ELSIF ELSE block to check book availability
-- ============================================================================

DO $$
DECLARE
    v_copies INT;
    v_book_title VARCHAR(100) := 'Database Systems';
BEGIN
    SELECT available_copies INTO v_copies 
    FROM books 
    WHERE title = v_book_title;

    IF v_copies = 0 THEN
        RAISE NOTICE 'Book "%" is UNAVAILABLE.', v_book_title;
    ELSIF v_copies <= 2 THEN
        RAISE NOTICE 'Book "%" is LOW ON COPIES (% left).', v_book_title, v_copies;
    ELSE
        RAISE NOTICE 'Book "%" is SUFFICIENTLY STOCKED (% left).', v_book_title, v_copies;
    END IF;
END $$;


-- ============================================================================
-- 3. WHILE loop (overdue reminders) & Numeric FOR loop (shelf numbers)
-- ============================================================================

DO $$
DECLARE
    v_reminder_count INT := 1;
BEGIN
    -- WHILE loop for three overdue reminder numbers
    RAISE NOTICE '--- Overdue Reminders ---';
    WHILE v_reminder_count <= 3 LOOP
        RAISE NOTICE 'Overdue Reminder #%', v_reminder_count;
        v_reminder_count := v_reminder_count + 1;
    END LOOP;

    -- Numeric FOR loop for three library shelf numbers
    RAISE NOTICE '--- Shelf Numbers ---';
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Library Shelf #%', i;
    END LOOP;
END $$;


-- ============================================================================
-- 4. Procedure borrow_book
-- ============================================================================

CREATE OR REPLACE PROCEDURE borrow_book(
    p_book_id INT,
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
        RAISE EXCEPTION 'Invalid loan quantity: %. Quantity must be greater than zero.', p_quantity;
    END IF;

    -- Check available copies
    SELECT available_copies INTO v_current_stock
    FROM books
    WHERE book_id = p_book_id;

    IF v_current_stock IS NULL THEN
        RAISE NOTICE 'Book ID % does not exist.', p_book_id;
        RETURN;
    END IF;

    IF v_current_stock < p_quantity THEN
        RAISE NOTICE 'Cannot borrow % copies of Book ID %. Only % available.', 
            p_quantity, p_book_id, v_current_stock;
        RETURN;
    END IF;

    -- Reduce stock
    UPDATE books
    SET available_copies = available_copies - p_quantity
    WHERE book_id = p_book_id;

    -- Record loan
    INSERT INTO book_loans (book_id, student_number, quantity, loan_status)
    VALUES (p_book_id, p_student_number, p_quantity, 'ACTIVE');

    RAISE NOTICE 'Successfully recorded loan for Student % (Book ID %, Qty: %).', 
        p_student_number, p_book_id, p_quantity;
END;
$$;


-- ============================================================================
-- 5. Call borrow_book for 2 valid loans and 1 exceeding available copies
-- ============================================================================

-- Valid loan 1 (Book 1: Database Systems, Qty 2)
CALL borrow_book(1, 'STU1001', 2);

-- Valid loan 2 (Book 2: Introduction to Algorithms, Qty 1)
CALL borrow_book(2, 'STU1002', 1);

-- Loan request exceeding stock (Book 2 now has 0 stock, requesting 1)
CALL borrow_book(2, 'STU1003', 1);

-- Query tables to inspect state
SELECT * FROM books;
SELECT * FROM book_loans;


-- ============================================================================
-- 6. Procedure return_book & double-call demonstration
-- ============================================================================

CREATE OR REPLACE PROCEDURE return_book(
    p_loan_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
    v_book_id INT;
    v_quantity INT;
BEGIN
    SELECT loan_status, book_id, quantity 
    INTO v_status, v_book_id, v_quantity
    FROM book_loans
    WHERE loan_id = p_loan_id;

    IF v_status IS NULL THEN
        RAISE NOTICE 'Loan ID % not found.', p_loan_id;
        RETURN;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan ID % is already marked RETURNED. Copies will NOT be restored again.', p_loan_id;
    ELSE
        -- Mark as returned
        UPDATE book_loans
        SET loan_status = 'RETURNED'
        WHERE loan_id = p_loan_id;

        -- Restore stock
        UPDATE books
        SET available_copies = available_copies + v_quantity
        WHERE book_id = v_book_id;

        RAISE NOTICE 'Loan ID % successfully returned. Restored % copies.', p_loan_id, v_quantity;
    END IF;
END;
$$;

-- Call return_book twice on Loan ID 1
CALL return_book(1);
CALL return_book(1); -- Second call will skip stock restoration


-- ============================================================================
-- 7. Explicit cursor to display books with few copies remaining (<= 2)
-- ============================================================================

DO $$
DECLARE
    rec_book RECORD;
    -- Explicit cursor definition
    cur_low_stock CURSOR FOR
        SELECT book_id, title, available_copies
        FROM books
        WHERE available_copies <= 2;
BEGIN
    RAISE NOTICE '--- Books with Few Copies Remaining ---';
    OPEN cur_low_stock;
    LOOP
        FETCH cur_low_stock INTO rec_book;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Book ID: %, Title: "%", Copies Remaining: %', 
            rec_book.book_id, rec_book.title, rec_book.available_copies;
    END LOOP;
    CLOSE cur_low_stock;
END $$;


-- ============================================================================
-- 8. Try borrowing 0 copies and handle exception
-- ============================================================================

DO $$
BEGIN
    CALL borrow_book(1, 'STU1004', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Caught Exception: %', SQLERRM;
END $$;


-- ============================================================================
-- 9. Final Verification Queries
-- ============================================================================

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;