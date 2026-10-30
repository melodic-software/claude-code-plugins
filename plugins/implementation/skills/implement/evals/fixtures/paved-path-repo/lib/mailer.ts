export interface Mail {
  to: string;
  subject: string;
  text: string;
}

export async function sendMail(mail: Mail): Promise<void> {
  await fetch(process.env.MAIL_API_URL!, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(mail),
  });
}
