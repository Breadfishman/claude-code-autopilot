def split_bill(total_cents, people):
    share, rem = divmod(total_cents, people)
    return [share + 1 if i < rem else share for i in range(people)]
