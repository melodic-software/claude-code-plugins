def active_emails(users):
    result = []
    for user in users:
        if user.get("active") is True:
            email = user.get("email")
            if email is not None:
                normalized = email.strip().lower()
                result.append(normalized)
            else:
                pass
    return result
