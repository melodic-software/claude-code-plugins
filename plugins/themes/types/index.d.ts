/** What the bedroom's settings card shows; the settings themselves stay in the module and the store. */
export type BedroomCard = {
  /** The id of the row the card stands in; an older row draws nothing. Absent until `/bedroom` places one. */
  row?: string
  /** How many rows `/bedroom` has placed this session: each gets an id of its own, so it stands at the transcript's end. */
  placed?: number
  /** The card shows above the prompt: no surface drew the placed row. */
  inBand?: boolean
  /** The card was closed: its hooks draw nothing until `/bedroom` shows it again. */
  isAway?: boolean
  /** Counts the changes made while the card is open, so each one draws the card again. */
  seen?: number
  /** What the last press on the card answered. */
  said?: string
}

declare module 'claude-code' {
  interface PluginState {
    themes: {
      'bedroom-card': Shaped<BedroomCard>
      /** The bedroom's minute chain: the time the newest copy of the module started it, so an older copy left running after a reload stops. */
      'bedroom-chain': number
    }
  }
}
