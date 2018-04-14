// environment vars
require('dotenv').load()
const console = require('better-console')
const {DATA_FILE_PATH} = process.env
// load data from JSON file
const people = require(DATA_FILE_PATH)
// utilities
const fs = require('mz/fs')
const path = require('path')

const OUTPUT_FILE_PATH = path.join(__dirname, 'gwwc_import.sql')
const POSTPROCESSING_FILE_PATH = path.join(__dirname, 'postprocessing.sql')

const tableSubstitutions = {
  default: {
    donations: 'donation_info'
  },
  specials: {
    recurringDonations: 'recurring_donations',
    reportedIncome: 'reported_income'
  }
}

const columnSubstitutions = {
  group: 'group_name',
  donation_timestamp: 'created_at'
}

const specialColumns = [
  'donations',
  'recurringDonations',
  'reportedIncome'
]

const specialColumnPrefixes = {
  donations: 'donation_',
  reported_income: 'income_',
  recurring_donations: 'recurring_donation_'
}

// magic happens here!
;(async function () {
  const sql = [] // holder for our SQL queries
  // step through all the people
  let i = 0;
  for (let Person of people.slice(123, 143).map(formatPerson)) {
    console.log(`Processing ${Person.person.first_name} ${Person.person.last_name}`)
    sql.push(`\n\n---- ${Person.person.first_name} ${Person.person.last_name}`)
    // go through each property
    // person table first, as other tables have foreign key refs
    sql.push(generateTableSQL('person', Person.person))
    // go through other tables, except person and specials
    for (let table in Person) {
      if (['person', 'specials'].includes(table)) continue // special tables handled below
      sql.push(generateTableSQL(table, Person[table]))
    }
    // handle special tables
    for (let table in Person.specials) {
      sql.push(generateSpecialTableSQL(table, Person.specials[table]))
    }
    // we can only generate 1024 unique ids per millisecond, and the import runs **fast**
    sql.push(`SELECT pg_sleep_for('5 milliseconds');`)
    i++;
  } // end main for loop
  // write sql out
  try {
    const postprocessingFile = await fs.readFile(POSTPROCESSING_FILE_PATH).then(d => d.toString())
    sql.push(postprocessingFile)
    await fs.writeFile(OUTPUT_FILE_PATH, sql.join('\n'))
    console.log(`All people processed!`)
    console.info(`Output saved to ${OUTPUT_FILE_PATH}`)
  } catch (err) {
    console.error(err)
  }
}())

// Helpers
function formatPerson (p) {
  const Person = {
    person: {},
    specials: {}
  }
  const delimiterRX = /__/
  for (let prop in p) {
    if (specialColumns.includes(prop)) {
      // table substitutions
      const table = tableSubstitutions.specials[prop] || prop
      // special table column substitutions
      const rows = !Array.isArray(p[prop]) ? p[prop] : p[prop].map(row => {
        const newRow = {}
        // column substituions
        for (let col in row) {
          const newCol = columnSubstitutions[col] || col
          newRow[newCol] = row[col]
        }
        return newRow
      })
      Person.specials[table] = rows
    } else if (delimiterRX.test(prop)) {
      const parts = prop.split(delimiterRX)
      // table substitutions
      const table = Object.keys(tableSubstitutions.default).includes(parts[0])
        ? tableSubstitutions.default[parts[0]]
        : parts[0]
      // column substitutions
      const column = columnSubstitutions[parts[1]] || parts[1]
      // set values
      Person[table] = Person[table] || {}
      Person[table][column] = p[prop]
    } else {
      Person.person[prop] = p[prop]
    }
  }
  return Person
}

function formatValue (value) {
  const delimiter = '$val$'
  if (typeof value === 'number') return value
  else if (!value) return 'NULL'
  else return `${delimiter}${value}${delimiter}`
}

function generateTableSQL (name, data) {
  const sql = []
  const cols = Object.keys(data) // get an array, to guarantee enumeration order
  if (cols.every(col => data[col] === null)) return '' // if this is an empty set, don't bother adding a record
  sql.push(`INSERT INTO gwwc_import.${name} (${cols.join(', ')}) VALUES`)
  sql.push(`  ${formatTableValues(data, cols)};`)
  return sql.join('\n')
}

function generateSpecialTableSQL (name, rows) {
  if (!Array.isArray(rows) || !rows.length) return ''
  const prefix = specialColumnPrefixes[name]
  const sql = []
  const newRows = []
  for (let row of rows) {
    const newRow = {}
    for (let col in row) {
      const newCol = prefix ? col.replace(prefix, '') : col
      newRow[newCol] = row[col]
    }
    newRows.push(newRow)
  }
  sql.push(`---- ${name}`)
  const cols = Object.keys(newRows[0]) // get an array, to guarantee enumeration order
  sql.push(`INSERT INTO gwwc_import.${name} (${cols.join(', ')}) VALUES`)
  sql.push(newRows.map(data => `  ${formatTableValues(data, cols)}`).join(',\n'))
  sql.push(`;`)
  return sql.join('\n')
}

function formatTableValues (data, cols) {
  return `(${cols.map(col => formatValue(data[col])).join(', ')})`
}
