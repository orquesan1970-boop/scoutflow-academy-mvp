// ScoutFlow Academy MVP sample data

const ScoutFlowData = {
  academy: {
    id: "academy_cbja",
    name: "CBJA Academy",
    sport: "Basketball",
    country: "Spain",
    city: "Alcalá de Henares"
  },

  players: [
    {
      id: "player_001",
      scoutflowId: "SF-2026-0001",
      firstName: "Pablo Ignacio",
      lastName: "Andrés Suárez",
      fullName: "Pablo Ignacio Andrés Suárez",
      birthDate: "2002-08-25",
      birthYear: 2002,
      age: 23,
      nationality: ["Argentina", "España"],
      residenceCountry: "",
      city: "",
      sport: "Baloncesto",
      primaryPosition: "Base",
      secondaryPosition: "Escolta",
      height: "1,86 m",
      weight: "",
      status: "Datos incompletos",
      scoutScore: null,
      documents: {
        passport: false,
        academic: false,
        medical: false
      },
      videos: {
        highlights: false,
        fullGame: false
      },
      familyAccess: false,
      notes: "Primer jugador real cargado para demo CBJA v0.1."
    }
  ],

  users: [
    {
      id: "user_jorge",
      name: "Jorge Andrés",
      email: "orquesan1970@gmail.com",
      role: "Director",
      access: "all"
    }
  ],

  pipeline: {
    "Nuevo": [],
    "Info incompleta": ["player_001"],
    "Evaluación": [],
    "Entrevista": [],
    "Oferta": [],
    "Aceptado": [],
    "Inscrito": []
  }
};
