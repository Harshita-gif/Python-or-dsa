-- ============================================================================
-- PROJECT: Banking Transaction Management System (Core Banking Simulation)
-- ENVIRONMENT: Oracle SQL & PL/SQL (Compatible with Oracle 11g, 12c, 18c, 19c, 21c, 23ai)
-- TOOLS: Oracle SQL Developer, SQL*Plus, TOAD
-- FILE FORMAT: Complete Self-Contained Source Code in a Single File
-- ============================================================================
-- DESCRIPTION:
-- A comprehensive, production-grade PL/SQL implementation of a Core Banking 
-- Transaction Management System. It features:
--   1. Customer Onboarding & KYC Management
--   2. Multi-Account Management (Savings, Current/Checking, Loan, Fixed Deposit)
--   3. Secure Intra-bank & Inter-bank Fund Transfers with ACID atomicity
--   4. Real-time Transaction Ledger & Mini Statement generation
--   5. Loan Lifecycle Management (Application, Risk Scoring, Approval, Disbursement, EMI Repayment)
--   6. Customer Support Ticket & Inquiry Management
--   7. Automated Triggers for Overdraft Prevention, Status Validation, & Audit Logging
--   8. Cursors for Batch Monthly Interest Calculation across all eligible accounts
--   9. Autonomous Transaction Error Logging & Robust Custom Exception Handling
--  10. Role-Based Views & a Comprehensive End-to-End Test Harness Block
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 200;
SET PAGESIZE 100;
SET FEEDBACK ON;

-- ============================================================================
-- SECTION 1: CLEANUP / DROP EXISTING OBJECTS (IDEMPOTENT SCRIPT EXECUTION)
-- ============================================================================
PROMPT >> Cleaning up existing banking schema objects...

DECLARE
    PROCEDURE drop_obj(p_name IN VARCHAR2, p_type IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE 'DROP ' || p_type || ' ' || p_name || 
            CASE WHEN p_type = 'TABLE' THEN ' CASCADE CONSTRAINTS PURGE' ELSE '' END;
        DBMS_OUTPUT.PUT_LINE('Dropped ' || p_type || ': ' || p_name);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-942, -2289, -4043, -12003) THEN
                DBMS_OUTPUT.PUT_LINE('Notice: ' || SQLERRM);
            END IF;
    END drop_obj;
BEGIN
    -- Drop Views
    drop_obj('VW_CUSTOMER_ACCOUNT_SUMMARY', 'VIEW');
    drop_obj('VW_LOAN_OFFICER_PORTAL', 'VIEW');
    drop_obj('VW_COMPLIANCE_TRANSACTION_AUDIT', 'VIEW');
    drop_obj('VW_DAILY_BANK_LEDGER', 'VIEW');

    -- Drop Package
    drop_obj('PKG_BANKING_CORE', 'PACKAGE');

    -- Drop Tables
    drop_obj('SUPPORT_TICKETS', 'TABLE');
    drop_obj('LOAN_REPAYMENT_SCHEDULE', 'TABLE');
    drop_obj('LOAN_ACCOUNTS', 'TABLE');
    drop_obj('LOAN_APPLICATIONS', 'TABLE');
    drop_obj('INTERBANK_TRANSFERS', 'TABLE');
    drop_obj('TRANSACTIONS', 'TABLE');
    drop_obj('ACCOUNTS', 'TABLE');
    drop_obj('CUSTOMERS', 'TABLE');
    drop_obj('BRANCHES', 'TABLE');
    drop_obj('AUDIT_LOGS', 'TABLE');
    drop_obj('ERROR_LOGS', 'TABLE');

    -- Drop Sequences
    drop_obj('SEQ_CUSTOMER_ID', 'SEQUENCE');
    drop_obj('SEQ_ACCOUNT_ID', 'SEQUENCE');
    drop_obj('SEQ_TXN_ID', 'SEQUENCE');
    drop_obj('SEQ_INTERBANK_ID', 'SEQUENCE');
    drop_obj('SEQ_LOAN_APP_ID', 'SEQUENCE');
    drop_obj('SEQ_LOAN_ACC_ID', 'SEQUENCE');
    drop_obj('SEQ_TICKET_ID', 'SEQUENCE');
    drop_obj('SEQ_AUDIT_ID', 'SEQUENCE');
    drop_obj('SEQ_ERROR_ID', 'SEQUENCE');
END;
/

-- ============================================================================
-- SECTION 2: SEQUENCES
-- ============================================================================
PROMPT >> Creating Sequences...

CREATE SEQUENCE SEQ_CUSTOMER_ID    START WITH 10001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_ACCOUNT_ID     START WITH 50001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_TXN_ID         START WITH 100001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_INTERBANK_ID   START WITH 70001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_LOAN_APP_ID    START WITH 80001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_LOAN_ACC_ID    START WITH 90001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_TICKET_ID      START WITH 30001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_AUDIT_ID       START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE SEQ_ERROR_ID       START WITH 1 INCREMENT BY 1 NOCACHE;

-- ============================================================================
-- SECTION 3: SCHEMA DDL (TABLE DEFINITIONS & CONSTRAINTS)
-- ============================================================================
PROMPT >> Creating Core Banking Tables...

-- 1. Bank Branches
CREATE TABLE BRANCHES (
    BRANCH_ID       NUMBER(5)           CONSTRAINT PK_BRANCHES PRIMARY KEY,
    BRANCH_CODE     VARCHAR2(10)        CONSTRAINT UQ_BRANCH_CODE UNIQUE NOT NULL,
    BRANCH_NAME     VARCHAR2(100)       NOT NULL,
    IFSC_CODE       VARCHAR2(15)        CONSTRAINT UQ_BRANCH_IFSC UNIQUE NOT NULL,
    CITY            VARCHAR2(50)        NOT NULL,
    STATE           VARCHAR2(50)        NOT NULL,
    CREATED_AT      DATE                DEFAULT SYSDATE NOT NULL
);

-- 2. Customer Profiles & KYC
CREATE TABLE CUSTOMERS (
    CUSTOMER_ID     NUMBER(10)          CONSTRAINT PK_CUSTOMERS PRIMARY KEY,
    FIRST_NAME      VARCHAR2(50)        NOT NULL,
    LAST_NAME       VARCHAR2(50)        NOT NULL,
    EMAIL           VARCHAR2(100)       CONSTRAINT UQ_CUST_EMAIL UNIQUE NOT NULL,
    PHONE           VARCHAR2(15)        CONSTRAINT UQ_CUST_PHONE UNIQUE NOT NULL,
    NATIONAL_ID     VARCHAR2(25)        CONSTRAINT UQ_CUST_NAT_ID UNIQUE NOT NULL,
    DATE_OF_BIRTH   DATE                NOT NULL,
    ADDRESS         VARCHAR2(250)       NOT NULL,
    RISK_CATEGORY   VARCHAR2(10)        DEFAULT 'LOW' NOT NULL,
    KYC_STATUS      VARCHAR2(15)        DEFAULT 'VERIFIED' NOT NULL,
    CREATED_AT      DATE                DEFAULT SYSDATE NOT NULL,
    CONSTRAINT CHK_CUST_KYC_STATUS CHECK (KYC_STATUS IN ('PENDING', 'VERIFIED', 'REJECTED', 'SUSPENDED')),
    CONSTRAINT CHK_CUST_RISK CHECK (RISK_CATEGORY IN ('LOW', 'MEDIUM', 'HIGH'))
);

-- 3. Customer Accounts (Savings, Current, Loan, Fixed Deposit)
CREATE TABLE ACCOUNTS (
    ACCOUNT_ID          NUMBER(10)          CONSTRAINT PK_ACCOUNTS PRIMARY KEY,
    ACCOUNT_NUMBER      VARCHAR2(20)        CONSTRAINT UQ_ACC_NUM UNIQUE NOT NULL,
    CUSTOMER_ID         NUMBER(10)          NOT NULL,
    BRANCH_ID           NUMBER(5)           NOT NULL,
    ACCOUNT_TYPE        VARCHAR2(15)        NOT NULL,
    BALANCE             NUMBER(15, 2)       DEFAULT 0.00 NOT NULL,
    OVERDRAFT_LIMIT     NUMBER(15, 2)       DEFAULT 0.00 NOT NULL,
    STATUS              VARCHAR2(15)        DEFAULT 'ACTIVE' NOT NULL,
    CURRENCY            VARCHAR2(5)         DEFAULT 'INR' NOT NULL,
    OPENED_AT           DATE                DEFAULT SYSDATE NOT NULL,
    LAST_ACTIVITY_AT    DATE                DEFAULT SYSDATE NOT NULL,
    CONSTRAINT FK_ACC_CUSTOMER FOREIGN KEY (CUSTOMER_ID) REFERENCES CUSTOMERS(CUSTOMER_ID) ON DELETE CASCADE,
    CONSTRAINT FK_ACC_BRANCH FOREIGN KEY (BRANCH_ID) REFERENCES BRANCHES(BRANCH_ID),
    CONSTRAINT CHK_ACC_TYPE CHECK (ACCOUNT_TYPE IN ('SAVINGS', 'CURRENT', 'LOAN', 'FIXED_DEPOSIT')),
    CONSTRAINT CHK_ACC_STATUS CHECK (STATUS IN ('ACTIVE', 'DORMANT', 'FROZEN', 'CLOSED')),
    CONSTRAINT CHK_ACC_OVERDRAFT CHECK (OVERDRAFT_LIMIT >= 0)
);

-- 4. Central Transaction Journal / Ledger
CREATE TABLE TRANSACTIONS (
    TXN_ID                  NUMBER(12)          CONSTRAINT PK_TRANSACTIONS PRIMARY KEY,
    TXN_REF_NO              VARCHAR2(35)        CONSTRAINT UQ_TXN_REF UNIQUE NOT NULL,
    ACCOUNT_ID              NUMBER(10)          NOT NULL,
    TXN_TYPE                VARCHAR2(25)        NOT NULL,
    AMOUNT                  NUMBER(15, 2)       NOT NULL,
    BALANCE_BEFORE          NUMBER(15, 2)       NOT NULL,
    BALANCE_AFTER           NUMBER(15, 2)       NOT NULL,
    COUNTERPARTY_ACC        VARCHAR2(35),
    COUNTERPARTY_BANK       VARCHAR2(50),
    DESCRIPTION             VARCHAR2(255)       NOT NULL,
    CHANNEL                 VARCHAR2(20)        DEFAULT 'ONLINE' NOT NULL,
    STATUS                  VARCHAR2(15)        DEFAULT 'SUCCESS' NOT NULL,
    TXN_TIMESTAMP           TIMESTAMP           DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT FK_TXN_ACCOUNT FOREIGN KEY (ACCOUNT_ID) REFERENCES ACCOUNTS(ACCOUNT_ID),
    CONSTRAINT CHK_TXN_TYPE CHECK (TXN_TYPE IN (
        'DEBIT', 'CREDIT', 'TRANSFER_IN', 'TRANSFER_OUT',
        'INTEREST_CREDIT', 'LOAN_DISBURSEMENT', 'LOAN_REPAYMENT', 'SERVICE_FEE'
    )),
    CONSTRAINT CHK_TXN_STATUS CHECK (STATUS IN ('SUCCESS', 'FAILED', 'REVERSED', 'PENDING')),
    CONSTRAINT CHK_TXN_CHANNEL CHECK (CHANNEL IN ('ONLINE', 'MOBILE', 'ATM', 'BRANCH', 'INTERNAL'))
);

-- 5. Interbank Transfers (External Bank Transfers Simulation)
CREATE TABLE INTERBANK_TRANSFERS (
    TRANSFER_ID             NUMBER(10)          CONSTRAINT PK_INTERBANK PRIMARY KEY,
    TXN_ID                  NUMBER(12)          NOT NULL,
    SOURCE_ACCOUNT_ID       NUMBER(10)          NOT NULL,
    BENEFICIARY_NAME        VARCHAR2(100)       NOT NULL,
    BENEFICIARY_ACC_NO      VARCHAR2(35)        NOT NULL,
    BENEFICIARY_IFSC        VARCHAR2(15)        NOT NULL,
    BENEFICIARY_BANK        VARCHAR2(80)        NOT NULL,
    AMOUNT                  NUMBER(15, 2)       NOT NULL,
    TRANSFER_FEE            NUMBER(10, 2)       DEFAULT 0.00 NOT NULL,
    TRANSFER_MODE           VARCHAR2(10)        DEFAULT 'NEFT' NOT NULL,
    STATUS                  VARCHAR2(15)        DEFAULT 'PROCESSED' NOT NULL,
    INITIATED_AT            DATE                DEFAULT SYSDATE NOT NULL,
    CONSTRAINT FK_IB_TXN FOREIGN KEY (TXN_ID) REFERENCES TRANSACTIONS(TXN_ID),
    CONSTRAINT FK_IB_SRC_ACC FOREIGN KEY (SOURCE_ACCOUNT_ID) REFERENCES ACCOUNTS(ACCOUNT_ID),
    CONSTRAINT CHK_IB_MODE CHECK (TRANSFER_MODE IN ('NEFT', 'RTGS', 'IMPS')),
    CONSTRAINT CHK_IB_STATUS CHECK (STATUS IN ('INITIATED', 'PROCESSED', 'FAILED', 'REJECTED'))
);

-- 6. Loan Applications
CREATE TABLE LOAN_APPLICATIONS (
    LOAN_APP_ID             NUMBER(10)          CONSTRAINT PK_LOAN_APP PRIMARY KEY,
    CUSTOMER_ID             NUMBER(10)          NOT NULL,
    LOAN_TYPE               VARCHAR2(25)        NOT NULL,
    REQUESTED_AMOUNT        NUMBER(15, 2)       NOT NULL,
    TENURE_MONTHS           NUMBER(3)           NOT NULL,
    PROPOSED_INTEREST_RATE  NUMBER(5, 2)        NOT NULL,
    PURPOSE                 VARCHAR2(250)       NOT NULL,
    STATUS                  VARCHAR2(15)        DEFAULT 'SUBMITTED' NOT NULL,
    REVIEWER_NOTES          VARCHAR2(300),
    ACTIONED_BY             VARCHAR2(50),
    APPLIED_AT              DATE                DEFAULT SYSDATE NOT NULL,
    ACTIONED_AT             DATE,
    CONSTRAINT FK_LOAN_APP_CUST FOREIGN KEY (CUSTOMER_ID) REFERENCES CUSTOMERS(CUSTOMER_ID),
    CONSTRAINT CHK_LOAN_TYPE CHECK (LOAN_TYPE IN ('PERSONAL', 'HOME', 'AUTO', 'EDUCATION', 'BUSINESS')),
    CONSTRAINT CHK_LOAN_STATUS CHECK (STATUS IN ('SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'DISBURSED')),
    CONSTRAINT CHK_LOAN_REQ_AMT CHECK (REQUESTED_AMOUNT > 0),
    CONSTRAINT CHK_LOAN_TENURE CHECK (TENURE_MONTHS > 0)
);

-- 7. Loan Servicing Accounts
CREATE TABLE LOAN_ACCOUNTS (
    LOAN_ACC_ID             NUMBER(10)          CONSTRAINT PK_LOAN_ACC PRIMARY KEY,
    LOAN_APP_ID             NUMBER(10)          CONSTRAINT UQ_LOAN_ACC_APP UNIQUE NOT NULL,
    DISBURSEMENT_ACC_ID     NUMBER(10)          NOT NULL,
    PRINCIPAL_AMOUNT        NUMBER(15, 2)       NOT NULL,
    ANNUAL_INTEREST_RATE    NUMBER(5, 2)        NOT NULL,
    TENURE_MONTHS           NUMBER(3)           NOT NULL,
    MONTHLY_EMI             NUMBER(15, 2)       NOT NULL,
    OUTSTANDING_PRINCIPAL   NUMBER(15, 2)       NOT NULL,
    TOTAL_INTEREST_PAYABLE  NUMBER(15, 2)       NOT NULL,
    START_DATE              DATE                DEFAULT SYSDATE NOT NULL,
    END_DATE                DATE                NOT NULL,
    LOAN_STATUS             VARCHAR2(15)        DEFAULT 'ACTIVE' NOT NULL,
    CONSTRAINT FK_LOAN_ACC_APP FOREIGN KEY (LOAN_APP_ID) REFERENCES LOAN_APPLICATIONS(LOAN_APP_ID),
    CONSTRAINT FK_LOAN_DISB_ACC FOREIGN KEY (DISBURSEMENT_ACC_ID) REFERENCES ACCOUNTS(ACCOUNT_ID),
    CONSTRAINT CHK_LOAN_ACC_STATUS CHECK (LOAN_STATUS IN ('ACTIVE', 'CLOSED', 'DEFAULTED'))
);

-- 8. Customer Support Tickets & Inquiries
CREATE TABLE SUPPORT_TICKETS (
    TICKET_ID               NUMBER(10)          CONSTRAINT PK_SUPPORT_TICKETS PRIMARY KEY,
    CUSTOMER_ID             NUMBER(10)          NOT NULL,
    ACCOUNT_ID              NUMBER(10),
    SUBJECT                 VARCHAR2(150)       NOT NULL,
    CATEGORY                VARCHAR2(30)        NOT NULL,
    MESSAGE_BODY            VARCHAR2(1000)      NOT NULL,
    AGENT_RESPONSE          VARCHAR2(1000),
    PRIORITY                VARCHAR2(10)        DEFAULT 'MEDIUM' NOT NULL,
    STATUS                  VARCHAR2(15)        DEFAULT 'OPEN' NOT NULL,
    CREATED_AT              DATE                DEFAULT SYSDATE NOT NULL,
    RESOLVED_AT             DATE,
    CONSTRAINT FK_SUPP_CUST FOREIGN KEY (CUSTOMER_ID) REFERENCES CUSTOMERS(CUSTOMER_ID),
    CONSTRAINT FK_SUPP_ACC FOREIGN KEY (ACCOUNT_ID) REFERENCES ACCOUNTS(ACCOUNT_ID),
    CONSTRAINT CHK_SUPP_CAT CHECK (CATEGORY IN ('TRANSACTION', 'ACCOUNT', 'LOAN', 'SECURITY', 'CARD_SERVICE', 'GENERAL')),
    CONSTRAINT CHK_SUPP_PRIO CHECK (PRIORITY IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    CONSTRAINT CHK_SUPP_STAT CHECK (STATUS IN ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED'))
);

-- 9. Central Security & Compliance Audit Log
CREATE TABLE AUDIT_LOGS (
    AUDIT_ID                NUMBER(12)          CONSTRAINT PK_AUDIT_LOGS PRIMARY KEY,
    EVENT_TYPE              VARCHAR2(50)        NOT NULL,
    ENTITY_NAME             VARCHAR2(50)        NOT NULL,
    ENTITY_ID               VARCHAR2(50)        NOT NULL,
    OLD_VALUE               VARCHAR2(400),
    NEW_VALUE               VARCHAR2(400),
    PERFORMED_BY            VARCHAR2(50)        DEFAULT USER NOT NULL,
    LOG_TIMESTAMP           TIMESTAMP           DEFAULT SYSTIMESTAMP NOT NULL
);

-- 10. Autonomous Exception & Error Log
CREATE TABLE ERROR_LOGS (
    ERROR_ID                NUMBER(12)          CONSTRAINT PK_ERROR_LOGS PRIMARY KEY,
    MODULE_NAME             VARCHAR2(60)        NOT NULL,
    ERROR_CODE              NUMBER              NOT NULL,
    ERROR_MESSAGE           VARCHAR2(400)       NOT NULL,
    CALL_STACK              VARCHAR2(2000),
    LOGGED_AT               TIMESTAMP           DEFAULT SYSTIMESTAMP NOT NULL
);

-- ============================================================================
-- SECTION 4: DATABASE TRIGGERS
-- ============================================================================
PROMPT >> Creating Automated Triggers...

-- Trigger 1: Enforce Account Rules (Overdraft Restrictions & Negative Balance Prevention)
CREATE OR REPLACE TRIGGER TRG_ENFORCE_ACCOUNT_LIMITS
BEFORE UPDATE OF BALANCE ON ACCOUNTS
FOR EACH ROW
DECLARE
    v_min_allowed_balance NUMBER(15, 2);
BEGIN
    -- For CURRENT accounts, overdraft is permitted up to OVERDRAFT_LIMIT
    IF :NEW.ACCOUNT_TYPE = 'CURRENT' THEN
        v_min_allowed_balance := -1 * :NEW.OVERDRAFT_LIMIT;
    ELSE
        -- For SAVINGS and others, balance cannot go below 0
        v_min_allowed_balance := 0.00;
    END IF;

    IF :NEW.BALANCE < v_min_allowed_balance THEN
        RAISE_APPLICATION_ERROR(-20001, 
            'Transaction Rejected: Account ' || :NEW.ACCOUNT_NUMBER || 
            ' exceeds allowable limits. Min Balance Allowed: ' || v_min_allowed_balance || 
            ', Attempted Balance: ' || :NEW.BALANCE);
    END IF;

    -- Update last activity timestamp automatically
    :NEW.LAST_ACTIVITY_AT := SYSDATE;
END;
/

-- Trigger 2: Prevent Transactions on Inactive/Frozen/Closed Accounts
CREATE OR REPLACE TRIGGER TRG_PREVENT_INACTIVE_ACC_OPS
BEFORE UPDATE OF BALANCE ON ACCOUNTS
FOR EACH ROW
BEGIN
    IF :OLD.STATUS != 'ACTIVE' THEN
        RAISE_APPLICATION_ERROR(-20002, 
            'Operation Prohibited: Account ' || :OLD.ACCOUNT_NUMBER || 
            ' is currently ' || :OLD.STATUS || '. Transactions are restricted.');
    END IF;
END;
/

-- Trigger 3: Audit Account Status & Balance Changes
CREATE OR REPLACE TRIGGER TRG_AUDIT_ACCOUNT_MODS
AFTER UPDATE OF STATUS, OVERDRAFT_LIMIT ON ACCOUNTS
FOR EACH ROW
BEGIN
    IF :OLD.STATUS != :NEW.STATUS THEN
        INSERT INTO AUDIT_LOGS (
            AUDIT_ID, EVENT_TYPE, ENTITY_NAME, ENTITY_ID, OLD_VALUE, NEW_VALUE, PERFORMED_BY
        ) VALUES (
            SEQ_AUDIT_ID.NEXTVAL, 'STATUS_CHANGE', 'ACCOUNTS', 
            TO_CHAR(:NEW.ACCOUNT_ID), :OLD.STATUS, :NEW.STATUS, USER
        );
    END IF;

    IF :OLD.OVERDRAFT_LIMIT != :NEW.OVERDRAFT_LIMIT THEN
        INSERT INTO AUDIT_LOGS (
            AUDIT_ID, EVENT_TYPE, ENTITY_NAME, ENTITY_ID, OLD_VALUE, NEW_VALUE, PERFORMED_BY
        ) VALUES (
            SEQ_AUDIT_ID.NEXTVAL, 'LIMIT_CHANGE', 'ACCOUNTS', 
            TO_CHAR(:NEW.ACCOUNT_ID), TO_CHAR(:OLD.OVERDRAFT_LIMIT), TO_CHAR(:NEW.OVERDRAFT_LIMIT), USER
        );
    END IF;
END;
/

-- ============================================================================
-- SECTION 5: PACKAGE SPECIFICATION: PKG_BANKING_CORE
-- ============================================================================
PROMPT >> Creating Package Specification: PKG_BANKING_CORE...

CREATE OR REPLACE PACKAGE PKG_BANKING_CORE AS
    -- Global Constants
    c_min_savings_opening_bal   CONSTANT NUMBER := 500.00;
    c_default_savings_rate      CONSTANT NUMBER := 4.25;  -- 4.25% Annual Interest Rate
    c_interbank_flat_fee        CONSTANT NUMBER := 5.00;

    -- Custom User-Defined Exception Identifiers
    ex_insufficient_funds       EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_insufficient_funds, -20001);

    ex_account_inactive         EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_account_inactive, -20002);

    ex_invalid_amount           EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_invalid_amount, -20003);

    ex_same_account_transfer    EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_same_account_transfer, -20004);

    ex_account_not_found        EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_account_not_found, -20005);

    ex_loan_not_approved        EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_loan_not_approved, -20006);

    -- Cursor Types
    TYPE t_txn_cursor IS REF CURSOR;

    -- Logging Procedure (Autonomous Transaction to persist logs even on rollback)
    PROCEDURE sp_log_error(
        p_module_name   IN VARCHAR2,
        p_error_code    IN NUMBER,
        p_error_msg     IN VARCHAR2,
        p_call_stack    IN VARCHAR2
    );

    -- Customer & Account Management
    PROCEDURE sp_onboard_customer(
        p_first_name        IN VARCHAR2,
        p_last_name         IN VARCHAR2,
        p_email             IN VARCHAR2,
        p_phone             IN VARCHAR2,
        p_national_id       IN VARCHAR2,
        p_dob               IN DATE,
        p_address           IN VARCHAR2,
        p_branch_id         IN NUMBER,
        p_account_type      IN VARCHAR2,
        p_initial_deposit   IN NUMBER,
        p_customer_id       OUT NUMBER,
        p_account_id        OUT NUMBER,
        p_account_number    OUT VARCHAR2
    );

    PROCEDURE sp_open_additional_account(
        p_customer_id       IN NUMBER,
        p_branch_id         IN NUMBER,
        p_account_type      IN VARCHAR2,
        p_overdraft_limit   IN NUMBER DEFAULT 0.00,
        p_initial_deposit   IN NUMBER DEFAULT 0.00,
        p_account_id        OUT NUMBER,
        p_account_number    OUT VARCHAR2
    );

    -- Cash Transactions
    PROCEDURE sp_deposit(
        p_account_id        IN NUMBER,
        p_amount            IN NUMBER,
        p_description       IN VARCHAR2 DEFAULT 'Cash Deposit at Branch',
        p_channel           IN VARCHAR2 DEFAULT 'BRANCH',
        p_txn_ref           OUT VARCHAR2
    );

    PROCEDURE sp_withdraw(
        p_account_id        IN NUMBER,
        p_amount            IN NUMBER,
        p_description       IN VARCHAR2 DEFAULT 'Cash Withdrawal',
        p_channel           IN VARCHAR2 DEFAULT 'ATM',
        p_txn_ref           OUT VARCHAR2
    );

    -- Fund Transfers
    PROCEDURE sp_transfer_intra_bank(
        p_source_acc_id     IN NUMBER,
        p_target_acc_id     IN NUMBER,
        p_amount            IN NUMBER,
        p_description       IN VARCHAR2 DEFAULT 'Internal Fund Transfer',
        p_channel           IN VARCHAR2 DEFAULT 'ONLINE',
        p_txn_ref           OUT VARCHAR2
    );

    PROCEDURE sp_transfer_inter_bank(
        p_source_acc_id         IN NUMBER,
        p_beneficiary_name      IN VARCHAR2,
        p_beneficiary_acc_no    IN VARCHAR2,
        p_beneficiary_ifsc      IN VARCHAR2,
        p_beneficiary_bank      IN VARCHAR2,
        p_amount                IN NUMBER,
        p_mode                  IN VARCHAR2 DEFAULT 'NEFT',
        p_txn_ref               OUT VARCHAR2
    );

    -- Loan Processing
    FUNCTION fn_calculate_monthly_emi(
        p_principal             IN NUMBER,
        p_annual_rate           IN NUMBER,
        p_tenure_months         IN NUMBER
    ) RETURN NUMBER;

    PROCEDURE sp_apply_loan(
        p_customer_id           IN NUMBER,
        p_loan_type             IN VARCHAR2,
        p_amount                IN NUMBER,
        p_tenure_months         IN NUMBER,
        p_purpose               IN VARCHAR2,
        p_loan_app_id           OUT NUMBER
    );

    PROCEDURE sp_review_loan(
        p_loan_app_id           IN NUMBER,
        p_decision              IN VARCHAR2, -- 'APPROVED' or 'REJECTED'
        p_approved_rate         IN NUMBER,
        p_reviewer_notes        IN VARCHAR2,
        p_officer_name          IN VARCHAR2
    );

    PROCEDURE sp_disburse_loan(
        p_loan_app_id           IN NUMBER,
        p_credit_account_id     IN NUMBER,
        p_loan_acc_id           OUT NUMBER
    );

    PROCEDURE sp_repay_loan_emi(
        p_loan_acc_id           IN NUMBER,
        p_source_account_id     IN NUMBER,
        p_txn_ref               OUT VARCHAR2
    );

    -- Batch Processing (Cursors)
    PROCEDURE sp_calculate_monthly_interest;

    -- Reporting & Statements
    PROCEDURE sp_get_mini_statement(
        p_account_id            IN NUMBER,
        p_num_records           IN NUMBER DEFAULT 5
    );

    -- Customer Support Service
    PROCEDURE sp_create_support_ticket(
        p_customer_id           IN NUMBER,
        p_account_id            IN NUMBER,
        p_subject               IN VARCHAR2,
        p_category              IN VARCHAR2,
        p_message               IN VARCHAR2,
        p_priority              IN VARCHAR2 DEFAULT 'MEDIUM',
        p_ticket_id             OUT NUMBER
    );

    PROCEDURE sp_resolve_support_ticket(
        p_ticket_id             IN NUMBER,
        p_agent_reply           IN VARCHAR2
    );

    -- Utility Functions
    FUNCTION fn_get_account_balance(p_account_id IN NUMBER) RETURN NUMBER;
    FUNCTION fn_generate_txn_ref(p_prefix IN VARCHAR2 DEFAULT 'TXN') RETURN VARCHAR2;

END PKG_BANKING_CORE;
/

-- ============================================================================
-- SECTION 6: PACKAGE BODY: PKG_BANKING_CORE
-- ============================================================================
PROMPT >> Creating Package Body: PKG_BANKING_CORE...

CREATE OR REPLACE PACKAGE BODY PKG_BANKING_CORE AS

    -- ------------------------------------------------------------------------
    -- HELPER: Autonomous Error Logger
    -- ------------------------------------------------------------------------
    PROCEDURE sp_log_error(
        p_module_name   IN VARCHAR2,
        p_error_code    IN NUMBER,
        p_error_msg     IN VARCHAR2,
        p_call_stack    IN VARCHAR2
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO ERROR_LOGS (
            ERROR_ID, MODULE_NAME, ERROR_CODE, ERROR_MESSAGE, CALL_STACK, LOGGED_AT
        ) VALUES (
            SEQ_ERROR_ID.NEXTVAL, p_module_name, p_error_code, SUBSTR(p_error_msg, 1, 400),
            SUBSTR(p_call_stack, 1, 2000), SYSTIMESTAMP
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
    END sp_log_error;

    -- ------------------------------------------------------------------------
    -- HELPER: Generate Unique Formatted Transaction Reference
    -- ------------------------------------------------------------------------
    FUNCTION fn_generate_txn_ref(p_prefix IN VARCHAR2 DEFAULT 'TXN') RETURN VARCHAR2 IS
    BEGIN
        RETURN p_prefix || '-' || TO_CHAR(SYSDATE, 'YYYYMMDD') || '-' || 
               LPAD(SEQ_TXN_ID.NEXTVAL, 6, '0');
    END fn_generate_txn_ref;

    -- ------------------------------------------------------------------------
    -- HELPER: Get Account Balance
    -- ------------------------------------------------------------------------
    FUNCTION fn_get_account_balance(p_account_id IN NUMBER) RETURN NUMBER IS
        v_balance NUMBER(15, 2);
    BEGIN
        SELECT BALANCE INTO v_balance FROM ACCOUNTS WHERE ACCOUNT_ID = p_account_id;
        RETURN v_balance;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20005, 'Account ID ' || p_account_id || ' does not exist.');
    END fn_get_account_balance;

    -- ------------------------------------------------------------------------
    -- MODULE 1: CUSTOMER ONBOARDING & ACCOUNT CREATION
    -- ------------------------------------------------------------------------
    PROCEDURE sp_onboard_customer(
        p_first_name        IN VARCHAR2,
        p_last_name         IN VARCHAR2,
        p_email             IN VARCHAR2,
        p_phone             IN VARCHAR2,
        p_national_id       IN VARCHAR2,
        p_dob               IN DATE,
        p_address           IN VARCHAR2,
        p_branch_id         IN NUMBER,
        p_account_type      IN VARCHAR2,
        p_initial_deposit   IN NUMBER,
        p_customer_id       OUT NUMBER,
        p_account_id        OUT NUMBER,
        p_account_number    OUT VARCHAR2
    ) IS
        v_cust_id   NUMBER;
        v_acc_id    NUMBER;
        v_acc_num   VARCHAR2(20);
        v_txn_ref   VARCHAR2(35);
    BEGIN
        -- Validation
        IF p_account_type = 'SAVINGS' AND p_initial_deposit < c_min_savings_opening_bal THEN
            RAISE_APPLICATION_ERROR(-20003, 'Minimum opening balance for Savings account is INR ' || c_min_savings_opening_bal);
        END IF;

        IF MONTHS_BETWEEN(SYSDATE, p_dob) / 12 < 18 THEN
            RAISE_APPLICATION_ERROR(-20003, 'Customer must be at least 18 years old to open an independent account.');
        END IF;

        -- Create Customer Profile
        v_cust_id := SEQ_CUSTOMER_ID.NEXTVAL;
        INSERT INTO CUSTOMERS (
            CUSTOMER_ID, FIRST_NAME, LAST_NAME, EMAIL, PHONE, NATIONAL_ID,
            DATE_OF_BIRTH, ADDRESS, RISK_CATEGORY, KYC_STATUS, CREATED_AT
        ) VALUES (
            v_cust_id, p_first_name, p_last_name, LOWER(p_email), p_phone, p_national_id,
            p_dob, p_address, 'LOW', 'VERIFIED', SYSDATE
        );

        -- Open Primary Account
        v_acc_id := SEQ_ACCOUNT_ID.NEXTVAL;
        v_acc_num := 'ACC' || TO_CHAR(v_acc_id);

        INSERT INTO ACCOUNTS (
            ACCOUNT_ID, ACCOUNT_NUMBER, CUSTOMER_ID, BRANCH_ID,
            ACCOUNT_TYPE, BALANCE, OVERDRAFT_LIMIT, STATUS, CURRENCY, OPENED_AT
        ) VALUES (
            v_acc_id, v_acc_num, v_cust_id, p_branch_id,
            p_account_type, p_initial_deposit, 
            CASE WHEN p_account_type = 'CURRENT' THEN 50000.00 ELSE 0.00 END,
            'ACTIVE', 'INR', SYSDATE
        );

        -- Record Initial Deposit Ledger Entry if > 0
        IF p_initial_deposit > 0 THEN
            v_txn_ref := fn_generate_txn_ref('INIT');
            INSERT INTO TRANSACTIONS (
                TXN_ID, TXN_REF_NO, ACCOUNT_ID, TXN_TYPE, AMOUNT,
                BALANCE_BEFORE, BALANCE_AFTER, DESCRIPTION, CHANNEL, STATUS
            ) VALUES (
                SEQ_TXN_ID.NEXTVAL, v_txn_ref, v_acc_id, 'CREDIT', p_initial_deposit,
                0.00, p_initial_deposit, 'Initial Account Opening Deposit', 'BRANCH', 'SUCCESS'
            );
        END IF;

        -- Return OUT parameters
        p_customer_id := v_cust_id;
        p_account_id := v_acc_id;
        p_account_number := v_acc_num;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Customer Onboarded Successfully: ID = ' || v_cust_id || ', Account No = ' || v_acc_num);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            sp_log_error('SP_ONBOARD_CUSTOMER', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_onboard_customer;

    PROCEDURE sp_open_additional_account(
        p_customer_id       IN NUMBER,
        p_branch_id         IN NUMBER,
        p_account_type      IN VARCHAR2,
        p_overdraft_limit   IN NUMBER DEFAULT 0.00,
        p_initial_deposit   IN NUMBER DEFAULT 0.00,
        p_account_id        OUT NUMBER,
        p_account_number    OUT VARCHAR2
    ) IS
        v_cust_exists NUMBER;
        v_acc_id      NUMBER;
        v_acc_num     VARCHAR2(20);
        v_txn_ref     VARCHAR2(35);
    BEGIN
        SELECT COUNT(*) INTO v_cust_exists FROM CUSTOMERS WHERE CUSTOMER_ID = p_customer_id;
        IF v_cust_exists = 0 THEN
            RAISE_APPLICATION_ERROR(-20005, 'Customer ID ' || p_customer_id || ' does not exist.');
        END IF;

        v_acc_id := SEQ_ACCOUNT_ID.NEXTVAL;
        v_acc_num := 'ACC' || TO_CHAR(v_acc_id);

        INSERT INTO ACCOUNTS (
            ACCOUNT_ID, ACCOUNT_NUMBER, CUSTOMER_ID, BRANCH_ID,
            ACCOUNT_TYPE, BALANCE, OVERDRAFT_LIMIT, STATUS, OPENED_AT
        ) VALUES (
            v_acc_id, v_acc_num, p_customer_id, p_branch_id,
            p_account_type, p_initial_deposit, p_overdraft_limit, 'ACTIVE', SYSDATE
        );

        IF p_initial_deposit > 0 THEN
            v_txn_ref := fn_generate_txn_ref('INIT');
            INSERT INTO TRANSACTIONS (
                TXN_ID, TXN_REF_NO, ACCOUNT_ID, TXN_TYPE, AMOUNT,
                BALANCE_BEFORE, BALANCE_AFTER, DESCRIPTION, CHANNEL, STATUS
            ) VALUES (
                SEQ_TXN_ID.NEXTVAL, v_txn_ref, v_acc_id, 'CREDIT', p_initial_deposit,
                0.00, p_initial_deposit, 'Opening Deposit for Account', 'BRANCH', 'SUCCESS'
            );
        END IF;

        p_account_id := v_acc_id;
        p_account_number := v_acc_num;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            sp_log_error('SP_OPEN_ADDITIONAL_ACCOUNT', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_open_additional_account;

    -- ------------------------------------------------------------------------
    -- MODULE 2: CASH DEPOSITS & WITHDRAWALS
    -- ------------------------------------------------------------------------
    PROCEDURE sp_deposit(
        p_account_id        IN NUMBER,
        p_amount            IN NUMBER,
        p_description       IN VARCHAR2 DEFAULT 'Cash Deposit at Branch',
        p_channel           IN VARCHAR2 DEFAULT 'BRANCH',
        p_txn_ref           OUT VARCHAR2
    ) IS
        v_bal_before NUMBER(15, 2);
        v_bal_after  NUMBER(15, 2);
    BEGIN
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'Deposit amount must be strictly greater than zero.');
        END IF;

        -- Lock account record for update
        SELECT BALANCE INTO v_bal_before
        FROM ACCOUNTS
        WHERE ACCOUNT_ID = p_account_id
        FOR UPDATE;

        v_bal_after := v_bal_before + p_amount;

        UPDATE ACCOUNTS
        SET BALANCE = v_bal_after
        WHERE ACCOUNT_ID = p_account_id;

        p_txn_ref := fn_generate_txn_ref('DEP');

        INSERT INTO TRANSACTIONS (
            TXN_ID, TXN_REF_NO, ACCOUNT_ID, TXN_TYPE, AMOUNT,
            BALANCE_BEFORE, BALANCE_AFTER, DESCRIPTION, CHANNEL, STATUS
        ) VALUES (
            SEQ_TXN_ID.NEXTVAL, p_txn_ref, p_account_id, 'CREDIT', p_amount,
            v_bal_before, v_bal_after, p_description, p_channel, 'SUCCESS'
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Deposit Successful [' || p_txn_ref || ']: Account ' || p_account_id || 
                             ' | Amount: ' || p_amount || ' | New Balance: ' || v_bal_after);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            sp_log_error('SP_DEPOSIT', -20005, 'Account ID ' || p_account_id || ' not found.', DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE_APPLICATION_ERROR(-20005, 'Account ID ' || p_account_id || ' not found.');
        WHEN OTHERS THEN
            ROLLBACK;
            sp_log_error('SP_DEPOSIT', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_deposit;

    PROCEDURE sp_withdraw(
        p_account_id        IN NUMBER,
        p_amount            IN NUMBER,
        p_description       IN VARCHAR2 DEFAULT 'Cash Withdrawal',
        p_channel           IN VARCHAR2 DEFAULT 'ATM',
        p_txn_ref           OUT VARCHAR2
    ) IS
        v_bal_before NUMBER(15, 2);
        v_bal_after  NUMBER(15, 2);
    BEGIN
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'Withdrawal amount must be strictly greater than zero.');
        END IF;

        SELECT BALANCE INTO v_bal_before
        FROM ACCOUNTS
        WHERE ACCOUNT_ID = p_account_id
        FOR UPDATE;

        v_bal_after := v_bal_before - p_amount;

        -- Update balance (Triggers will enforce overdraft/balance restrictions)
        UPDATE ACCOUNTS
        SET BALANCE = v_bal_after
        WHERE ACCOUNT_ID = p_account_id;

        p_txn_ref := fn_generate_txn_ref('WTH');

        INSERT INTO TRANSACTIONS (
            TXN_ID, TXN_REF_NO, ACCOUNT_ID, TXN_TYPE, AMOUNT,
            BALANCE_BEFORE, BALANCE_AFTER, DESCRIPTION, CHANNEL, STATUS
        ) VALUES (
            SEQ_TXN_ID.NEXTVAL, p_txn_ref, p_account_id, 'DEBIT', p_amount,
            v_bal_before, v_bal_after, p_description, p_channel, 'SUCCESS'
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Withdrawal Successful [' || p_txn_ref || ']: Account ' || p_account_id || 
                             ' | Amount: ' || p_amount || ' | Remaining Balance: ' || v_bal_after);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            sp_log_error('SP_WITHDRAW', -20005, 'Account ID ' || p_account_id || ' not found.', DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE_APPLICATION_ERROR(-20005, 'Account ID ' || p_account_id || ' not found.');
        WHEN OTHERS THEN
            ROLLBACK;
            sp_log_error('SP_WITHDRAW', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_withdraw;

    -- ------------------------------------------------------------------------
    -- MODULE 3: FUND TRANSFERS (INTRA-BANK & INTER-BANK)
    -- ------------------------------------------------------------------------
    PROCEDURE sp_transfer_intra_bank(
        p_source_acc_id     IN NUMBER,
        p_target_acc_id     IN NUMBER,
        p_amount            IN NUMBER,
        p_description       IN VARCHAR2 DEFAULT 'Internal Fund Transfer',
        p_channel           IN VARCHAR2 DEFAULT 'ONLINE',
        p_txn_ref           OUT VARCHAR2
    ) IS
        v_src_bal_before NUMBER(15, 2);
        v_src_bal_after  NUMBER(15, 2);
        v_tgt_bal_before NUMBER(15, 2);
        v_tgt_bal_after  NUMBER(15, 2);
        v_src_acc_num    VARCHAR2(20);
        v_tgt_acc_num    VARCHAR2(20);
    BEGIN
        -- Basic validations
        IF p_source_acc_id = p_target_acc_id THEN
            RAISE_APPLICATION_ERROR(-20004, 'Transfer rejected: Source and Destination accounts cannot be the same.');
        END IF;

        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'Transfer amount must be strictly positive.');
        END IF;

        SAVEPOINT sp_before_transfer;

        -- Lock both accounts in deterministic order to prevent database deadlocks
        IF p_source_acc_id < p_target_acc_id THEN
            SELECT BALANCE, ACCOUNT_NUMBER INTO v_src_bal_before, v_src_acc_num
            FROM ACCOUNTS WHERE ACCOUNT_ID = p_source_acc_id FOR UPDATE;

            SELECT BALANCE, ACCOUNT_NUMBER INTO v_tgt_bal_before, v_tgt_acc_num
            FROM ACCOUNTS WHERE ACCOUNT_ID = p_target_acc_id FOR UPDATE;
        ELSE
            SELECT BALANCE, ACCOUNT_NUMBER INTO v_tgt_bal_before, v_tgt_acc_num
            FROM ACCOUNTS WHERE ACCOUNT_ID = p_target_acc_id FOR UPDATE;

            SELECT BALANCE, ACCOUNT_NUMBER INTO v_src_bal_before, v_src_acc_num
            FROM ACCOUNTS WHERE ACCOUNT_ID = p_source_acc_id FOR UPDATE;
        END IF;

        v_src_bal_after := v_src_bal_before - p_amount;
        v_tgt_bal_after := v_tgt_bal_before + p_amount;

        -- Update source account
        UPDATE ACCOUNTS SET BALANCE = v_src_bal_after WHERE ACCOUNT_ID = p_source_acc_id;

        -- Update target account
        UPDATE ACCOUNTS SET BALANCE = v_tgt_bal_after WHERE ACCOUNT_ID = p_target_acc_id;

        -- Shared Transfer Reference
        p_txn_ref := fn_generate_txn_ref('TXF');

        -- Log Debit on Source Account
        INSERT INTO TRANSACTIONS (
            TXN_ID, TXN_REF_NO, ACCOUNT_ID, TXN_TYPE, AMOUNT,
            BALANCE_BEFORE, BALANCE_AFTER, COUNTERPARTY_ACC, COUNTERPARTY_BANK,
            DESCRIPTION, CHANNEL, STATUS
        ) VALUES (
            SEQ_TXN_ID.NEXTVAL, p_txn_ref || '-DR', p_source_acc_id, 'TRANSFER_OUT', p_amount,
            v_src_bal_before, v_src_bal_after, v_tgt_acc_num, 'INTERNAL',
            p_description || ' to ' || v_tgt_acc_num, p_channel, 'SUCCESS'
        );

        -- Log Credit on Target Account
        INSERT INTO TRANSACTIONS (
            TXN_ID, TXN_REF_NO, ACCOUNT_ID, TXN_TYPE, AMOUNT,
            BALANCE_BEFORE, BALANCE_AFTER, COUNTERPARTY_ACC, COUNTERPARTY_BANK,
            DESCRIPTION, CHANNEL, STATUS
        ) VALUES (
            SEQ_TXN_ID.NEXTVAL, p_txn_ref || '-CR', p_target_acc_id, 'TRANSFER_IN', p_amount,
            v_tgt_bal_before, v_tgt_bal_after, v_src_acc_num, 'INTERNAL',
            p_description || ' from ' || v_src_acc_num, p_channel, 'SUCCESS'
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Intra-Bank Transfer Completed [' || p_txn_ref || ']: INR ' || p_amount || 
                             ' from ' || v_src_acc_num || ' to ' || v_tgt_acc_num);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK TO sp_before_transfer;
            sp_log_error('SP_TRANSFER_INTRA_BANK', -20005, 'One of the accounts does not exist.', DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE_APPLICATION_ERROR(-20005, 'One or both account IDs provided do not exist.');
        WHEN OTHERS THEN
            ROLLBACK TO sp_before_transfer;
            sp_log_error('SP_TRANSFER_INTRA_BANK', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_transfer_intra_bank;

    PROCEDURE sp_transfer_inter_bank(
        p_source_acc_id         IN NUMBER,
        p_beneficiary_name      IN VARCHAR2,
        p_beneficiary_acc_no    IN VARCHAR2,
        p_beneficiary_ifsc      IN VARCHAR2,
        p_beneficiary_bank      IN VARCHAR2,
        p_amount                IN NUMBER,
        p_mode                  IN VARCHAR2 DEFAULT 'NEFT',
        p_txn_ref               OUT VARCHAR2
    ) IS
        v_total_deduction NUMBER(15, 2);
        v_src_bal_before  NUMBER(15, 2);
        v_src_bal_after   NUMBER(15, 2);
        v_txn_id          NUMBER;
    BEGIN
        IF p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'Transfer amount must be strictly greater than zero.');
        END IF;

        v_total_deduction := p_amount + c_interbank_flat_fee;

        SAVEPOINT sp_before_interbank;

        SELECT BALANCE INTO v_src_bal_before
        FROM ACCOUNTS
        WHERE ACCOUNT_ID = p_source_acc_id
        FOR UPDATE;

        v_src_bal_after := v_src_bal_before - v_total_deduction;

        UPDATE ACCOUNTS
        SET BALANCE = v_src_bal_after
        WHERE ACCOUNT_ID = p_source_acc_id;

        p_txn_ref := fn_generate_txn_ref('IBT');
        v_txn_id := SEQ_TXN_ID.NEXTVAL;

        -- Record primary ledger transaction
        INSERT INTO TRANSACTIONS (
            TXN_ID, TXN_REF_NO, ACCOUNT_ID, TXN_TYPE, AMOUNT,
            BALANCE_BEFORE, BALANCE_AFTER, COUNTERPARTY_ACC, COUNTERPARTY_BANK,
            DESCRIPTION, CHANNEL, STATUS
        ) VALUES (
            v_txn_id, p_txn_ref, p_source_acc_id, 'TRANSFER_OUT', v_total_deduction,
            v_src_bal_before, v_src_bal_after, p_beneficiary_acc_no, p_beneficiary_bank,
            p_mode || ' Transfer to ' || p_beneficiary_name || ' (' || p_beneficiary_ifsc || ') [Incl Fee: INR ' || c_interbank_flat_fee || ']',
            'ONLINE', 'SUCCESS'
        );

        -- Record interbank clearing entry
        INSERT INTO INTERBANK_TRANSFERS (
            TRANSFER_ID, TXN_ID, SOURCE_ACCOUNT_ID, BENEFICIARY_NAME,
            BENEFICIARY_ACC_NO, BENEFICIARY_IFSC, BENEFICIARY_BANK,
            AMOUNT, TRANSFER_FEE, TRANSFER_MODE, STATUS, INITIATED_AT
        ) VALUES (
            SEQ_INTERBANK_ID.NEXTVAL, v_txn_id, p_source_acc_id, p_beneficiary_name,
            p_beneficiary_acc_no, p_beneficiary_ifsc, p_beneficiary_bank,
            p_amount, c_interbank_flat_fee, p_mode, 'PROCESSED', SYSDATE
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Interbank Transfer Completed [' || p_txn_ref || ']: INR ' || p_amount || 
                             ' sent to ' || p_beneficiary_name || ' at ' || p_beneficiary_bank);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK TO sp_before_interbank;
            sp_log_error('SP_TRANSFER_INTER_BANK', -20005, 'Source account not found.', DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE_APPLICATION_ERROR(-20005, 'Source account ID does not exist.');
        WHEN OTHERS THEN
            ROLLBACK TO sp_before_interbank;
            sp_log_error('SP_TRANSFER_INTER_BANK', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_transfer_inter_bank;

    -- ------------------------------------------------------------------------
    -- MODULE 4: LOAN APPLICATIONS & APPROVAL TRACKING
    -- ------------------------------------------------------------------------
    FUNCTION fn_calculate_monthly_emi(
        p_principal             IN NUMBER,
        p_annual_rate           IN NUMBER,
        p_tenure_months         IN NUMBER
    ) RETURN NUMBER IS
        v_monthly_rate  NUMBER;
        v_factor        NUMBER;
        v_emi           NUMBER(15, 2);
    BEGIN
        IF p_principal <= 0 OR p_tenure_months <= 0 THEN
            RETURN 0.00;
        END IF;

        IF p_annual_rate = 0 THEN
            RETURN ROUND(p_principal / p_tenure_months, 2);
        END IF;

        -- Monthly interest rate: r = (annual_rate / 12) / 100
        v_monthly_rate := (p_annual_rate / 12) / 100;
        
        -- Formula: EMI = P * r * (1+r)^n / ((1+r)^n - 1)
        v_factor := POWER(1 + v_monthly_rate, p_tenure_months);
        v_emi := ROUND(p_principal * v_monthly_rate * (v_factor / (v_factor - 1)), 2);

        RETURN v_emi;
    END fn_calculate_monthly_emi;

    PROCEDURE sp_apply_loan(
        p_customer_id           IN NUMBER,
        p_loan_type             IN VARCHAR2,
        p_amount                IN NUMBER,
        p_tenure_months         IN NUMBER,
        p_purpose               IN VARCHAR2,
        p_loan_app_id           OUT NUMBER
    ) IS
        v_app_id NUMBER;
        v_proposed_rate NUMBER(5, 2);
    BEGIN
        -- Assign indicative rate based on loan type
        v_proposed_rate := CASE p_loan_type
            WHEN 'HOME' THEN 8.50
            WHEN 'AUTO' THEN 9.25
            WHEN 'EDUCATION' THEN 7.50
            WHEN 'BUSINESS' THEN 11.50
            ELSE 12.00 -- PERSONAL
        END;

        v_app_id := SEQ_LOAN_APP_ID.NEXTVAL;

        INSERT INTO LOAN_APPLICATIONS (
            LOAN_APP_ID, CUSTOMER_ID, LOAN_TYPE, REQUESTED_AMOUNT,
            TENURE_MONTHS, PROPOSED_INTEREST_RATE, PURPOSE, STATUS, APPLIED_AT
        ) VALUES (
            v_app_id, p_customer_id, p_loan_type, p_amount,
            p_tenure_months, v_proposed_rate, p_purpose, 'SUBMITTED', SYSDATE
        );

        p_loan_app_id := v_app_id;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Loan Application Submitted: App ID = ' || v_app_id || ' | Amount: ' || p_amount);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            sp_log_error('SP_APPLY_LOAN', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_apply_loan;

    PROCEDURE sp_review_loan(
        p_loan_app_id           IN NUMBER,
        p_decision              IN VARCHAR2,
        p_approved_rate         IN NUMBER,
        p_reviewer_notes        IN VARCHAR2,
        p_officer_name          IN VARCHAR2
    ) IS
        v_curr_status VARCHAR2(15);
    BEGIN
        IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN
            RAISE_APPLICATION_ERROR(-20003, 'Invalid decision. Must be APPROVED or REJECTED.');
        END IF;

        SELECT STATUS INTO v_curr_status
        FROM LOAN_APPLICATIONS
        WHERE LOAN_APP_ID = p_loan_app_id
        FOR UPDATE;

        IF v_curr_status != 'SUBMITTED' AND v_curr_status != 'UNDER_REVIEW' THEN
            RAISE_APPLICATION_ERROR(-20006, 'Loan application is already in status ' || v_curr_status);
        END IF;

        UPDATE LOAN_APPLICATIONS
        SET STATUS = p_decision,
            PROPOSED_INTEREST_RATE = NVL(p_approved_rate, PROPOSED_INTEREST_RATE),
            REVIEWER_NOTES = p_reviewer_notes,
            ACTIONED_BY = p_officer_name,
            ACTIONED_AT = SYSDATE
        WHERE LOAN_APP_ID = p_loan_app_id;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Loan Application ' || p_loan_app_id || ' decision recorded: ' || p_decision);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            sp_log_error('SP_REVIEW_LOAN', -20005, 'Loan Application ID ' || p_loan_app_id || ' not found.', DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE_APPLICATION_ERROR(-20005, 'Loan Application ID not found.');
        WHEN OTHERS THEN
            ROLLBACK;
            sp_log_error('SP_REVIEW_LOAN', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_review_loan;

    PROCEDURE sp_disburse_loan(
        p_loan_app_id           IN NUMBER,
        p_credit_account_id     IN NUMBER,
        p_loan_acc_id           OUT NUMBER
    ) IS
        v_status        VARCHAR2(15);
        v_principal     NUMBER(15, 2);
        v_rate          NUMBER(5, 2);
        v_tenure        NUMBER(3);
        v_emi           NUMBER(15, 2);
        v_tot_interest  NUMBER(15, 2);
        v_new_loan_id   NUMBER;
        v_txn_ref       VARCHAR2(35);
        v_bal_before    NUMBER(15, 2);
        v_bal_after     NUMBER(15, 2);
    BEGIN
        SELECT STATUS, REQUESTED_AMOUNT, PROPOSED_INTEREST_RATE, TENURE_MONTHS
        INTO v_status, v_principal, v_rate, v_tenure
        FROM LOAN_APPLICATIONS
        WHERE LOAN_APP_ID = p_loan_app_id
        FOR UPDATE;

        IF v_status != 'APPROVED' THEN
            RAISE_APPLICATION_ERROR(-20006, 'Cannot disburse loan. Application status is ' || v_status || ' (Requires APPROVED).');
        END IF;

        v_emi := fn_calculate_monthly_emi(v_principal, v_rate, v_tenure);
        v_tot_interest := ROUND((v_emi * v_tenure) - v_principal, 2);

        v_new_loan_id := SEQ_LOAN_ACC_ID.NEXTVAL;

        -- Create active loan servicing account
        INSERT INTO LOAN_ACCOUNTS (
            LOAN_ACC_ID, LOAN_APP_ID, DISBURSEMENT_ACC_ID, PRINCIPAL_AMOUNT,
            ANNUAL_INTEREST_RATE, TENURE_MONTHS, MONTHLY_EMI, OUTSTANDING_PRINCIPAL,
            TOTAL_INTEREST_PAYABLE, START_DATE, END_DATE, LOAN_STATUS
        ) VALUES (
            v_new_loan_id, p_loan_app_id, p_credit_account_id, v_principal,
            v_rate, v_tenure, v_emi, v_principal,
            v_tot_interest, SYSDATE, ADD_MONTHS(SYSDATE, v_tenure), 'ACTIVE'
        );

        -- Credit Customer's Deposit Account with Disbursed Principal
        SELECT BALANCE INTO v_bal_before FROM ACCOUNTS WHERE ACCOUNT_ID = p_credit_account_id FOR UPDATE;
        v_bal_after := v_bal_before + v_principal;

        UPDATE ACCOUNTS SET BALANCE = v_bal_after WHERE ACCOUNT_ID = p_credit_account_id;

        v_txn_ref := fn_generate_txn_ref('DISB');

        INSERT INTO TRANSACTIONS (
            TXN_ID, TXN_REF_NO, ACCOUNT_ID, TXN_TYPE, AMOUNT,
            BALANCE_BEFORE, BALANCE_AFTER, DESCRIPTION, CHANNEL, STATUS
        ) VALUES (
            SEQ_TXN_ID.NEXTVAL, v_txn_ref, p_credit_account_id, 'LOAN_DISBURSEMENT', v_principal,
            v_bal_before, v_bal_after, 'Disbursement of Approved Loan #' || p_loan_app_id, 'INTERNAL', 'SUCCESS'
        );

        -- Update Application Status to DISBURSED
        UPDATE LOAN_APPLICATIONS SET STATUS = 'DISBURSED' WHERE LOAN_APP_ID = p_loan_app_id;

        p_loan_acc_id := v_new_loan_id;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Loan Disbursed Successfully: Loan Account = ' || v_new_loan_id || 
                             ' | Credited to Account = ' || p_credit_account_id || ' | Monthly EMI = INR ' || v_emi);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            sp_log_error('SP_DISBURSE_LOAN', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_disburse_loan;

    PROCEDURE sp_repay_loan_emi(
        p_loan_acc_id           IN NUMBER,
        p_source_account_id     IN NUMBER,
        p_txn_ref               OUT VARCHAR2
    ) IS
        v_emi           NUMBER(15, 2);
        v_outstanding   NUMBER(15, 2);
        v_loan_status   VARCHAR2(15);
        v_bal_before    NUMBER(15, 2);
        v_bal_after     NUMBER(15, 2);
    BEGIN
        SELECT MONTHLY_EMI, OUTSTANDING_PRINCIPAL, LOAN_STATUS
        INTO v_emi, v_outstanding, v_loan_status
        FROM LOAN_ACCOUNTS
        WHERE LOAN_ACC_ID = p_loan_acc_id
        FOR UPDATE;

        IF v_loan_status != 'ACTIVE' THEN
            RAISE_APPLICATION_ERROR(-20006, 'Loan Account is not active (Status: ' || v_loan_status || ')');
        END IF;

        -- Debit customer account
        SELECT BALANCE INTO v_bal_before FROM ACCOUNTS WHERE ACCOUNT_ID = p_source_account_id FOR UPDATE;
        v_bal_after := v_bal_before - v_emi;
        UPDATE ACCOUNTS SET BALANCE = v_bal_after WHERE ACCOUNT_ID = p_source_account_id;

        -- Update outstanding balance
        v_outstanding := GREATEST(0, v_outstanding - v_emi);
        UPDATE LOAN_ACCOUNTS
        SET OUTSTANDING_PRINCIPAL = v_outstanding,
            LOAN_STATUS = CASE WHEN v_outstanding = 0 THEN 'CLOSED' ELSE 'ACTIVE' END
        WHERE LOAN_ACC_ID = p_loan_acc_id;

        p_txn_ref := fn_generate_txn_ref('EMI');

        INSERT INTO TRANSACTIONS (
            TXN_ID, TXN_REF_NO, ACCOUNT_ID, TXN_TYPE, AMOUNT,
            BALANCE_BEFORE, BALANCE_AFTER, DESCRIPTION, CHANNEL, STATUS
        ) VALUES (
            SEQ_TXN_ID.NEXTVAL, p_txn_ref, p_source_account_id, 'LOAN_REPAYMENT', v_emi,
            v_bal_before, v_bal_after, 'EMI Payment for Loan Account #' || p_loan_acc_id, 'ONLINE', 'SUCCESS'
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Loan EMI Repayment Processed [' || p_txn_ref || ']: EMI = INR ' || v_emi || 
                             ' | Remaining Principal: ' || v_outstanding);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            sp_log_error('SP_REPAY_LOAN_EMI', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_repay_loan_emi;

    -- ------------------------------------------------------------------------
    -- MODULE 5: BATCH PROCESSING (CURSORS) FOR MONTHLY INTEREST ACCRUAL
    -- ------------------------------------------------------------------------
    PROCEDURE sp_calculate_monthly_interest IS
        -- Explicit Cursor to loop through all active SAVINGS accounts
        CURSOR cur_savings_accounts IS
            SELECT ACCOUNT_ID, ACCOUNT_NUMBER, BALANCE
            FROM ACCOUNTS
            WHERE ACCOUNT_TYPE = 'SAVINGS'
              AND STATUS = 'ACTIVE'
              AND BALANCE > 0
            FOR UPDATE OF BALANCE;

        v_monthly_interest NUMBER(15, 2);
        v_new_balance      NUMBER(15, 2);
        v_txn_ref          VARCHAR2(35);
        v_processed_count  NUMBER := 0;
        v_total_credited   NUMBER(15, 2) := 0.00;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('====================================================');
        DBMS_OUTPUT.PUT_LINE('STARTING BATCH MONTHLY INTEREST ACCRUAL (SAVINGS)');
        DBMS_OUTPUT.PUT_LINE('====================================================');

        FOR rec IN cur_savings_accounts LOOP
            -- Monthly rate = Annual Rate / 12
            v_monthly_interest := ROUND(rec.BALANCE * (c_default_savings_rate / 100) / 12, 2);

            IF v_monthly_interest > 0 THEN
                v_new_balance := rec.BALANCE + v_monthly_interest;

                -- Update account balance
                UPDATE ACCOUNTS
                SET BALANCE = v_new_balance
                WHERE CURRENT OF cur_savings_accounts;

                v_txn_ref := fn_generate_txn_ref('INT');

                -- Write transaction ledger
                INSERT INTO TRANSACTIONS (
                    TXN_ID, TXN_REF_NO, ACCOUNT_ID, TXN_TYPE, AMOUNT,
                    BALANCE_BEFORE, BALANCE_AFTER, DESCRIPTION, CHANNEL, STATUS
                ) VALUES (
                    SEQ_TXN_ID.NEXTVAL, v_txn_ref, rec.ACCOUNT_ID, 'INTEREST_CREDIT', v_monthly_interest,
                    rec.BALANCE, v_new_balance, 'Monthly Savings Interest @ ' || c_default_savings_rate || '% p.a.',
                    'INTERNAL', 'SUCCESS'
                );

                v_processed_count := v_processed_count + 1;
                v_total_credited := v_total_credited + v_monthly_interest;

                DBMS_OUTPUT.PUT_LINE('Acc: ' || rec.ACCOUNT_NUMBER || ' | Bal: ' || rec.BALANCE || 
                                     ' | Interest: +' || v_monthly_interest || ' | New Bal: ' || v_new_balance);
            END IF;
        END LOOP;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('BATCH INTEREST COMPLETED. Accounts Credited: ' || v_processed_count || 
                             ' | Total Interest Disbursed: INR ' || v_total_credited);
        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            sp_log_error('SP_CALCULATE_MONTHLY_INTEREST', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_calculate_monthly_interest;

    -- ------------------------------------------------------------------------
    -- MODULE 6: TRANSACTION HISTORY & MINI STATEMENT
    -- ------------------------------------------------------------------------
    PROCEDURE sp_get_mini_statement(
        p_account_id            IN NUMBER,
        p_num_records           IN NUMBER DEFAULT 5
    ) IS
        v_acc_num   VARCHAR2(20);
        v_cust_name VARCHAR2(100);
        v_balance   NUMBER(15, 2);
        v_type      VARCHAR2(15);

        -- Cursor to fetch last N transactions (Compatible across Oracle 11g through 23ai)
        CURSOR cur_history IS
            SELECT * FROM (
                SELECT TXN_REF_NO, TXN_TYPE, AMOUNT, BALANCE_AFTER, 
                       TO_CHAR(TXN_TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS') AS TXN_TIME,
                       DESCRIPTION
                FROM TRANSACTIONS
                WHERE ACCOUNT_ID = p_account_id
                ORDER BY TXN_TIMESTAMP DESC, TXN_ID DESC
            )
            WHERE ROWNUM <= p_num_records;
    BEGIN
        SELECT a.ACCOUNT_NUMBER, c.FIRST_NAME || ' ' || c.LAST_NAME, a.BALANCE, a.ACCOUNT_TYPE
        INTO v_acc_num, v_cust_name, v_balance, v_type
        FROM ACCOUNTS a
        JOIN CUSTOMERS c ON a.CUSTOMER_ID = c.CUSTOMER_ID
        WHERE a.ACCOUNT_ID = p_account_id;

        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('                           BANK MINI STATEMENT                                    ');
        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('Account Holder : ' || RPAD(v_cust_name, 30) || ' Account Number: ' || v_acc_num);
        DBMS_OUTPUT.PUT_LINE('Account Type   : ' || RPAD(v_type, 30)      || ' Current Balance: INR ' || TO_CHAR(v_balance, '999,999,990.00'));
        DBMS_OUTPUT.PUT_LINE('Recent Transactions (Last ' || p_num_records || '):');
        DBMS_OUTPUT.PUT_LINE(RPAD('TXN REF', 22) || RPAD('DATE/TIME', 20) || RPAD('TYPE', 18) || RPAD('AMOUNT (INR)', 15) || 'BALANCE');
        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------------------');

        FOR rec IN cur_history LOOP
            DBMS_OUTPUT.PUT_LINE(
                RPAD(rec.TXN_REF_NO, 22) ||
                RPAD(rec.TXN_TIME, 20) ||
                RPAD(rec.TXN_TYPE, 18) ||
                RPAD(TO_CHAR(rec.AMOUNT, '999,990.00'), 15) ||
                TO_CHAR(rec.BALANCE_AFTER, '999,999,990.00')
            );
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------------------');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            sp_log_error('SP_GET_MINI_STATEMENT', -20005, 'Account ' || p_account_id || ' does not exist.', DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE_APPLICATION_ERROR(-20005, 'Account ' || p_account_id || ' not found.');
        WHEN OTHERS THEN
            sp_log_error('SP_GET_MINI_STATEMENT', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_get_mini_statement;

    -- ------------------------------------------------------------------------
    -- MODULE 7: CUSTOMER SUPPORT CHAT & INQUIRIES
    -- ------------------------------------------------------------------------
    PROCEDURE sp_create_support_ticket(
        p_customer_id           IN NUMBER,
        p_account_id            IN NUMBER,
        p_subject               IN VARCHAR2,
        p_category              IN VARCHAR2,
        p_message               IN VARCHAR2,
        p_priority              IN VARCHAR2 DEFAULT 'MEDIUM',
        p_ticket_id             OUT NUMBER
    ) IS
        v_tid NUMBER;
    BEGIN
        v_tid := SEQ_TICKET_ID.NEXTVAL;

        INSERT INTO SUPPORT_TICKETS (
            TICKET_ID, CUSTOMER_ID, ACCOUNT_ID, SUBJECT, CATEGORY,
            MESSAGE_BODY, PRIORITY, STATUS, CREATED_AT
        ) VALUES (
            v_tid, p_customer_id, p_account_id, p_subject, p_category,
            p_message, p_priority, 'OPEN', SYSDATE
        );

        p_ticket_id := v_tid;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Support Ticket Logged: Ticket #' || v_tid || ' | Priority: ' || p_priority);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            sp_log_error('SP_CREATE_SUPPORT_TICKET', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_create_support_ticket;

    PROCEDURE sp_resolve_support_ticket(
        p_ticket_id             IN NUMBER,
        p_agent_reply           IN VARCHAR2
    ) IS
    BEGIN
        UPDATE SUPPORT_TICKETS
        SET STATUS = 'RESOLVED',
            AGENT_RESPONSE = p_agent_reply,
            RESOLVED_AT = SYSDATE
        WHERE TICKET_ID = p_ticket_id;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20005, 'Support Ticket #' || p_ticket_id || ' not found.');
        END IF;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Support Ticket #' || p_ticket_id || ' marked RESOLVED.');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            sp_log_error('SP_RESOLVE_SUPPORT_TICKET', SQLCODE, SQLERRM, DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END sp_resolve_support_ticket;

END PKG_BANKING_CORE;
/

-- ============================================================================
-- SECTION 7: ROLE-BASED ACCESS VIEWS & MONITORING
-- ============================================================================
PROMPT >> Creating Role-Based Views & Reports...

-- View 1: Customer Account Summary (Used by Web Banking / Mobile App)
CREATE OR REPLACE VIEW VW_CUSTOMER_ACCOUNT_SUMMARY AS
SELECT 
    c.CUSTOMER_ID,
    c.FIRST_NAME || ' ' || c.LAST_NAME AS CUSTOMER_NAME,
    c.EMAIL,
    c.PHONE,
    a.ACCOUNT_ID,
    a.ACCOUNT_NUMBER,
    a.ACCOUNT_TYPE,
    a.BALANCE,
    a.OVERDRAFT_LIMIT,
    a.STATUS AS ACCOUNT_STATUS,
    b.BRANCH_NAME,
    b.IFSC_CODE
FROM CUSTOMERS c
JOIN ACCOUNTS a ON c.CUSTOMER_ID = a.CUSTOMER_ID
JOIN BRANCHES b ON a.BRANCH_ID = b.BRANCH_ID;

-- View 2: Loan Officer Review Pipeline
CREATE OR REPLACE VIEW VW_LOAN_OFFICER_PORTAL AS
SELECT 
    la.LOAN_APP_ID,
    c.CUSTOMER_ID,
    c.FIRST_NAME || ' ' || c.LAST_NAME AS APPLICANT_NAME,
    c.RISK_CATEGORY,
    la.LOAN_TYPE,
    la.REQUESTED_AMOUNT,
    la.TENURE_MONTHS,
    la.PROPOSED_INTEREST_RATE,
    la.STATUS AS APPLICATION_STATUS,
    la.PURPOSE,
    la.APPLIED_AT
FROM LOAN_APPLICATIONS la
JOIN CUSTOMERS c ON la.CUSTOMER_ID = c.CUSTOMER_ID;

-- View 3: Compliance & Transaction Audit Ledger
CREATE OR REPLACE VIEW VW_COMPLIANCE_TRANSACTION_AUDIT AS
SELECT 
    t.TXN_ID,
    t.TXN_REF_NO,
    t.ACCOUNT_ID,
    a.ACCOUNT_NUMBER,
    t.TXN_TYPE,
    t.AMOUNT,
    t.BALANCE_BEFORE,
    t.BALANCE_AFTER,
    t.COUNTERPARTY_ACC,
    t.COUNTERPARTY_BANK,
    t.CHANNEL,
    t.STATUS,
    t.TXN_TIMESTAMP
FROM TRANSACTIONS t
JOIN ACCOUNTS a ON t.ACCOUNT_ID = a.ACCOUNT_ID;

-- View 4: Daily Banking Liquidity Ledger
CREATE OR REPLACE VIEW VW_DAILY_BANK_LEDGER AS
SELECT 
    TRUNC(TXN_TIMESTAMP) AS TXN_DATE,
    TXN_TYPE,
    COUNT(*) AS TOTAL_TXNS,
    SUM(AMOUNT) AS TOTAL_VOLUME,
    AVG(AMOUNT) AS AVG_TRANSACTION_SIZE
FROM TRANSACTIONS
GROUP BY TRUNC(TXN_TIMESTAMP), TXN_TYPE;

-- ============================================================================
-- SECTION 8: SEED DATA (BRANCH SETUP)
-- ============================================================================
PROMPT >> Seeding Branch Master Data...

INSERT INTO BRANCHES (BRANCH_ID, BRANCH_CODE, BRANCH_NAME, IFSC_CODE, CITY, STATE)
VALUES (101, 'BR-MUM01', 'Mumbai Central Flagship Branch', 'CORP0001001', 'Mumbai', 'Maharashtra');

INSERT INTO BRANCHES (BRANCH_ID, BRANCH_CODE, BRANCH_NAME, IFSC_CODE, CITY, STATE)
VALUES (102, 'BR-DEL01', 'New Delhi Connaught Place Branch', 'CORP0001002', 'New Delhi', 'Delhi');

INSERT INTO BRANCHES (BRANCH_ID, BRANCH_CODE, BRANCH_NAME, IFSC_CODE, CITY, STATE)
VALUES (103, 'BR-BLR01', 'Bengaluru IT Corridor Branch', 'CORP0001003', 'Bengaluru', 'Karnataka');

COMMIT;

-- ============================================================================
-- SECTION 9: END-TO-END DEMONSTRATION & TEST HARNESS
-- ============================================================================
PROMPT >> Running Automated Test Harness Demonstration...

DECLARE
    -- Customer 1 variables (Alice)
    v_cust1_id      NUMBER;
    v_acc1_id       NUMBER;
    v_acc1_num      VARCHAR2(20);

    -- Customer 2 variables (Bob)
    v_cust2_id      NUMBER;
    v_acc2_id       NUMBER;
    v_acc2_num      VARCHAR2(20);

    -- Auxiliary variables
    v_txn_ref       VARCHAR2(35);
    v_loan_app_id   NUMBER;
    v_loan_acc_id   NUMBER;
    v_ticket_id     NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('==================================================================================');
    DBMS_OUTPUT.PUT_LINE('                   CORE BANKING SYSTEM TEST HARNESS INITIALIZING                  ');
    DBMS_OUTPUT.PUT_LINE('==================================================================================');

    -- STEP 1: Onboard Customer 1 (Alice Sharma) with a Savings Account
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- [TEST 1: CUSTOMER ONBOARDING (ALICE)] ---');
    PKG_BANKING_CORE.sp_onboard_customer(
        p_first_name      => 'Alice',
        p_last_name       => 'Sharma',
        p_email           => 'alice.sharma@example.com',
        p_phone           => '+919876543210',
        p_national_id     => 'PAN-ABCD1234E',
        p_dob             => TO_DATE('1994-06-15', 'YYYY-MM-DD'),
        p_address         => '104 Marina Towers, Bandra West, Mumbai',
        p_branch_id       => 101,
        p_account_type    => 'SAVINGS',
        p_initial_deposit => 15000.00,
        p_customer_id     => v_cust1_id,
        p_account_id      => v_acc1_id,
        p_account_number  => v_acc1_num
    );

    -- STEP 2: Onboard Customer 2 (Bob Miller) with a Current Account
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- [TEST 2: CUSTOMER ONBOARDING (BOB)] ---');
    PKG_BANKING_CORE.sp_onboard_customer(
        p_first_name      => 'Bob',
        p_last_name       => 'Miller',
        p_email           => 'bob.miller@enterprise.com',
        p_phone           => '+919811223344',
        p_national_id     => 'PAN-WXYZ9876Q',
        p_dob             => TO_DATE('1988-11-20', 'YYYY-MM-DD'),
        p_address         => '52 Cyber City, Gurugram',
        p_branch_id       => 102,
        p_account_type    => 'CURRENT',
        p_initial_deposit => 25000.00,
        p_customer_id     => v_cust2_id,
        p_account_id      => v_acc2_id,
        p_account_number  => v_acc2_num
    );

    -- STEP 3: Deposit and Withdrawal Testing
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- [TEST 3: CASH DEPOSIT & WITHDRAWAL] ---');
    PKG_BANKING_CORE.sp_deposit(
        p_account_id  => v_acc1_id,
        p_amount      => 5000.00,
        p_description => 'Cheque Deposit clearance',
        p_channel     => 'BRANCH',
        p_txn_ref     => v_txn_ref
    );

    PKG_BANKING_CORE.sp_withdraw(
        p_account_id  => v_acc1_id,
        p_amount      => 2000.00,
        p_description => 'ATM Cash Withdrawal',
        p_channel     => 'ATM',
        p_txn_ref     => v_txn_ref
    );

    -- STEP 4: Internal Fund Transfer (Alice -> Bob)
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- [TEST 4: INTRA-BANK FUND TRANSFER] ---');
    PKG_BANKING_CORE.sp_transfer_intra_bank(
        p_source_acc_id => v_acc1_id,
        p_target_acc_id => v_acc2_id,
        p_amount        => 4500.00,
        p_description   => 'Rent sharing reimbursement',
        p_channel       => 'MOBILE',
        p_txn_ref       => v_txn_ref
    );

    -- STEP 5: External Interbank Transfer (Alice -> External Bank Beneficiary)
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- [TEST 5: INTER-BANK TRANSFER (NEFT/IMPS)] ---');
    PKG_BANKING_CORE.sp_transfer_inter_bank(
        p_source_acc_id      => v_acc1_id,
        p_beneficiary_name   => 'David Warner',
        p_beneficiary_acc_no => '98765432101234',
        p_beneficiary_ifsc   => 'HDFC0000456',
        p_beneficiary_bank   => 'HDFC Bank Ltd',
        p_amount             => 3000.00,
        p_mode               => 'IMPS',
        p_txn_ref            => v_txn_ref
    );

    -- STEP 6: Negative Testing / Overdraft Trigger Protection
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- [TEST 6: OVERDRAFT EXCEPTION HANDLING TEST] ---');
    BEGIN
        -- Attempt to withdraw more than Alice's savings balance (which has 0 overdraft)
        PKG_BANKING_CORE.sp_withdraw(
            p_account_id  => v_acc1_id,
            p_amount      => 1000000.00, -- Unrealistic excessive amount
            p_description => 'Attempted Overdraft',
            p_channel     => 'ONLINE',
            p_txn_ref     => v_txn_ref
        );
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('>> [SUCCESSFULLY CAUGHT EXPECTED OVERDRAFT RESTRICTION]: ' || SQLERRM);
    END;

    -- STEP 7: Batch Monthly Interest Accrual via Explicit Cursor Loop
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- [TEST 7: BATCH MONTHLY INTEREST ACCRUAL] ---');
    PKG_BANKING_CORE.sp_calculate_monthly_interest;

    -- STEP 8: Loan Application, Review, Approval, Disbursement & EMI Repayment
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- [TEST 8: LOAN LIFECYCLE (APPLY -> APPROVE -> DISBURSE -> REPAY)] ---');
    
    -- Alice applies for a Home Loan of INR 500,000 for 60 months
    PKG_BANKING_CORE.sp_apply_loan(
        p_customer_id   => v_cust1_id,
        p_loan_type     => 'HOME',
        p_amount        => 500000.00,
        p_tenure_months => 60,
        p_purpose       => 'Apartment interior renovation',
        p_loan_app_id   => v_loan_app_id
    );

    -- Credit Officer reviews and approves loan application
    PKG_BANKING_CORE.sp_review_loan(
        p_loan_app_id    => v_loan_app_id,
        p_decision       => 'APPROVED',
        p_approved_rate  => 8.50,
        p_reviewer_notes => 'KYC and Credit score verified (Score: 790). Approved at 8.50% p.a.',
        p_officer_name   => 'Rajesh Khanna (Chief Credit Manager)'
    );

    -- Disburse approved loan amount into Alice's savings account
    PKG_BANKING_CORE.sp_disburse_loan(
        p_loan_app_id       => v_loan_app_id,
        p_credit_account_id => v_acc1_id,
        p_loan_acc_id       => v_loan_acc_id
    );

    -- Repay 1 Month EMI
    PKG_BANKING_CORE.sp_repay_loan_emi(
        p_loan_acc_id       => v_loan_acc_id,
        p_source_account_id => v_acc1_id,
        p_txn_ref           => v_txn_ref
    );

    -- STEP 9: Customer Support Ticket & Resolution
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- [TEST 9: CUSTOMER SUPPORT CHAT & TICKET SYSTEM] ---');
    PKG_BANKING_CORE.sp_create_support_ticket(
        p_customer_id => v_cust1_id,
        p_account_id  => v_acc1_id,
        p_subject     => 'Debit card international transactions activation',
        p_category    => 'CARD_SERVICE',
        p_message     => 'Hello, I am traveling next week. Please enable international contactless payments.',
        p_priority    => 'HIGH',
        p_ticket_id   => v_ticket_id
    );

    PKG_BANKING_CORE.sp_resolve_support_ticket(
        p_ticket_id   => v_ticket_id,
        p_agent_reply => 'Your international contactless usage has been activated for 30 days.'
    );

    -- STEP 10: Generate Formatted Mini Statements for Both Accounts
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- [TEST 10: ACCOUNT MINI STATEMENTS] ---');
    PKG_BANKING_CORE.sp_get_mini_statement(p_account_id => v_acc1_id, p_num_records => 6);
    PKG_BANKING_CORE.sp_get_mini_statement(p_account_id => v_acc2_id, p_num_records => 4);

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '==================================================================================');
    DBMS_OUTPUT.PUT_LINE('             CORE BANKING TEST HARNESS EXECUTION COMPLETED SUCCESSFULLY           ');
    DBMS_OUTPUT.PUT_LINE('==================================================================================');
END;
/

-- ============================================================================
-- SECTION 10: VERIFICATION QUERIES (SUMMARY OUTPUT)
-- ============================================================================
PROMPT >> Displaying Final Account Summary View...
SELECT * FROM VW_CUSTOMER_ACCOUNT_SUMMARY;

PROMPT >> Displaying Loan Officer Portal View...
SELECT * FROM VW_LOAN_OFFICER_PORTAL;

PROMPT >> Displaying Daily Banking Ledger Volume...
SELECT * FROM VW_DAILY_BANK_LEDGER;

PROMPT >> Displaying Audit Trail Entries...
SELECT AUDIT_ID, EVENT_TYPE, ENTITY_NAME, ENTITY_ID, OLD_VALUE, NEW_VALUE, LOG_TIMESTAMP 
FROM AUDIT_LOGS 
ORDER BY AUDIT_ID ASC;

PROMPT >> Displaying Error Logs (Should be empty or contain caught tests only)...
SELECT ERROR_ID, MODULE_NAME, ERROR_CODE, ERROR_MESSAGE, LOGGED_AT 
FROM ERROR_LOGS 
ORDER BY ERROR_ID ASC;

PROMPT >> Core Banking Simulation script finished successfully.
