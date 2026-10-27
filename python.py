"""
Number Guessing Game
A complete Python mini project featuring:
  - 'random' module for secret number generation
  - 'while' loops for game replay and turn progression
  - 'if / elif / else' conditional structures for hints and evaluation
  - Input validation (try/except) to avoid crashes on non-integer inputs
  - Multiple difficulty levels and score tracking
"""

import sys
import random

# Ensure safe output across all Windows, Mac, and Linux consoles
if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


def display_banner():
    """Prints the game header."""
    print("=" * 60)
    print("            WELCOME TO THE NUMBER GUESSING GAME            ")
    print("=" * 60)
    print("  I am thinking of a number between a given range.")
    print("  Can you guess it within the allowed attempts?\n")


def choose_difficulty():
    """Lets the player select a difficulty level using a while loop and if/elif."""
    print("Select Difficulty Level:")
    print("  [1] Easy   : Range 1 - 50   (10 Attempts)")
    print("  [2] Medium : Range 1 - 100  (7 Attempts)")
    print("  [3] Hard   : Range 1 - 200  (5 Attempts)")

    while True:
        try:
            choice = input("Enter choice (1/2/3) [Default: 2]: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nExiting game.")
            sys.exit(0)

        if choice == "" or choice == "2":
            return 1, 100, 7
        elif choice == "1":
            return 1, 50, 10
        elif choice == "3":
            return 1, 200, 5
        else:
            print("  [!] Invalid choice. Please enter 1, 2, or 3.")


def play_round():
    """Executes a single round of the guessing game."""
    min_num, max_num, max_attempts = choose_difficulty()
    
    # 1. Random module generates the secret number
    secret_number = random.randint(min_num, max_num)
    attempts_used = 0
    has_won = False

    print(f"\n[+] I have picked a secret number between {min_num} and {max_num}.")
    print(f"[+] You have {max_attempts} attempts. Good luck!\n")

    # 2. Core game loop using 'while'
    while attempts_used < max_attempts:
        remaining = max_attempts - attempts_used
        print(f"--- Attempt {attempts_used + 1}/{max_attempts} ({remaining} remaining) ---")
        
        try:
            user_input = input(f"Enter your guess ({min_num}-{max_num}): ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nGame interrupted. Exiting round.")
            return False, attempts_used

        # Input validation (prevents crashes on invalid strings)
        try:
            guess = int(user_input)
        except ValueError:
            print("  [X] Invalid input! Please enter a valid whole number.\n")
            continue

        # Range check
        if guess < min_num or guess > max_num:
            print(f"  [!] Out of bounds! Your guess must be between {min_num} and {max_num}.\n")
            continue

        attempts_used += 1

        # 3. Conditional evaluation using 'if / elif / else'
        if guess == secret_number:
            has_won = True
            break
        elif guess < secret_number:
            difference = secret_number - guess
            if difference <= 5:
                print("  [^] Too Low, but VERY close! (Within 5 numbers)\n")
            else:
                print("  [^] Too Low! Try a higher number.\n")
        else:
            difference = guess - secret_number
            if difference <= 5:
                print("  [v] Too High, but VERY close! (Within 5 numbers)\n")
            else:
                print("  [v] Too High! Try a lower number.\n")

    # Round Results
    print("=" * 60)
    if has_won:
        score = (max_attempts - attempts_used + 1) * 10
        print(f"  *** BINGO! YOU GOT IT! ***")
        print(f"  Secret Number : {secret_number}")
        print(f"  Attempts Taken: {attempts_used}/{max_attempts}")
        print(f"  Round Score   : {score} points")
    else:
        print(f"  [GAME OVER] You ran out of attempts.")
        print(f"  The secret number was: {secret_number}")
    print("=" * 60)

    return has_won, attempts_used


def main():
    display_banner()
    rounds_played = 0
    rounds_won = 0
    best_attempt = float("inf")

    # 4. Main session replay loop using 'while'
    while True:
        rounds_played += 1
        won, attempts = play_round()

        if won:
            rounds_won += 1
            if attempts < best_attempt:
                best_attempt = attempts

        print("\nSession Stats:")
        print(f"  Rounds Played: {rounds_played} | Won: {rounds_won} | Win Rate: {(rounds_won/rounds_played)*100:.1f}%")
        if best_attempt != float("inf"):
            print(f"  Best Round: Solved in {best_attempt} guess(es)!")

        try:
            play_again = input("\nDo you want to play again? (yes/no) [Default: no]: ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            play_again = "no"

        if play_again not in ["y", "yes"]:
            print("\nThanks for playing! Goodbye!\n")
            break
        print("\n" + "#" * 60 + "\n")


if __name__ == "__main__":
    main()